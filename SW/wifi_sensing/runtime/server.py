import argparse
import base64
from collections import deque
import csv
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import mimetypes
import os
from pathlib import Path
import sys
import threading
import time
from urllib.parse import urlparse, parse_qs
import uuid
import zipfile
from live_timing import LiveClock
from radio import upgrade_record, board_layout

from core import read_signal, source_id, parse_csi_line, inspect_signal, estimate_rate, train_baseline

ROOT = Path(__file__).resolve().parent
REPO = ROOT / 'resources' if getattr(sys, 'frozen', False) else ROOT.parent
DATA = Path(os.environ.get('WIFI_SENSING2_DATA_DIR') or (
    Path(sys.executable).parent / 'WifiSensing2.0-data' if getattr(sys, 'frozen', False) else ROOT / 'data-v2'))
SESSIONS = DATA / 'sessions'
SEGMENTS = DATA / 'segments'
MODELS = DATA / 'models'
for folder in (SESSIONS, SEGMENTS, MODELS):
    folder.mkdir(parents=True, exist_ok=True)

CATALOG = [{'id': 'raw-breathing', 'name': '호흡 실험 · 원본 CSI 30초',
            'path': 'SOOM-AI/data/bpm/1005bpm.csv', 'kind': 'raw_iq_52', 'label': '미라벨',
            'note': '저장소 bpm 폴더의 실측 기록. 행동 구간의 정답 주석은 제공되지 않았습니다.'}]
for key, name in [('walk', '걷기'), ('lie', '누워 있기'), ('rustle', '뒤척임')]:
    for number in range(1, 6):
        CATALOG.append({'id': f'{key}-{number}', 'name': f'{name} {number} · 전처리 4초',
                        'path': f'SOOM-AI/preprocessed/{key}/{key} ({number}).npy', 'kind': 'processed_1d',
                        'label': name, 'note': '저장소 파일명 기준 라벨. 원본 I/Q는 없으며, 시간축은 60 Hz 가정입니다.'})
CACHE = {}
LOCK = threading.RLock()


def write_json(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), encoding='utf-8')
    temp.replace(path)


def summary(session):
    frames = session['frames']
    return {k: v for k, v in session.items() if k != 'frames'} | {
        'count': len(frames), 'start': frames[0]['t'] if frames else 0,
        'end': frames[-1]['t'] if frames else 0, 'duration': frames[-1]['t'] - frames[0]['t'] if frames else 0}


def make_session(blob, filename, rate=60, origin='import', note='', suggested_label='미라벨'):
    frames, kind, quality = read_signal(blob, filename, rate)
    sid = source_id(blob, kind, rate)
    return {'id': sid, 'name': filename, 'frames': frames, 'representation': kind, 'quality': quality,
            'source_path': origin, 'suggested_label': suggested_label, 'note': note,
            'experiment_id': sid, 'created_at': datetime.now(timezone.utc).isoformat()}


def load_session(sid):
    with LOCK:
        if sid == LIVE.sid:
            return LIVE.snapshot()
        if sid in CACHE:
            return CACHE[sid]
    item = next((x for x in CATALOG if x['id'] == sid), None)
    if item:
        file = REPO / item['path']
        result = make_session(file.read_bytes(), file.name, origin=item['path'], note=item['note'], suggested_label=item['label'])
        write_json(SESSIONS / f"{result['id']}.json", result)
        with LOCK:
            CACHE[sid] = result
            CACHE[result['id']] = result
        return result
    if not sid.isalnum() or len(sid) > 40:
        raise ValueError('잘못된 기록 ID입니다.')
    file = SESSIONS / f'{sid}.json'
    if not file.exists():
        raise ValueError('기록을 찾을 수 없습니다.')
    result = upgrade_record(json.loads(file.read_text(encoding='utf-8')))
    with LOCK:
        CACHE[sid] = result
    return result


class LiveReader:
    def __init__(self):
        self.sid = ''
        self.port = None
        self.thread = None
        self.stop_event = threading.Event()
        self.frames = deque(maxlen=60000)
        self.error = ''
        self.rejected = 0
        self.received = 0
        self.device = ''
        self.header = None
        self.log_path = None
        self.started_at = 0.0
        self.board_info = {}
        self.networks = []
        self.event_seq = 0
        self.last_event = ''
        self.control_lock = threading.Lock()
        self.clock_tracker = LiveClock()
        self.warmup_frames = 0

    def elapsed(self):
        return time.perf_counter() - self.started_at if self.started_at else 0.0

    def snapshot(self):
        return {'id': self.sid, 'name': f'실시간 {self.device}', 'frames': list(self.frames),
                'representation': 'raw_iq_52', 'source_path': 'live_serial', 'experiment_id': self.sid,
                'suggested_label': '미라벨', 'quality': {'rejected': self.rejected, 'time_basis': 'device_aligned_when_available',
                'warmup_frames': self.warmup_frames,
                'received': self.received, 'trimmed': max(0, self.received - len(self.frames))},
                'note': '장치 시간이 있으면 수신 시각에 정렬한 장치 시간축을 사용합니다. 재접속 직후 시간 확인 전 데이터는 표시·학습에서 제외합니다. 원래 장치 시간과 수신 시각·I/Q는 저널에 보존됩니다.',
                'journal': self.log_path.name if self.log_path else None}

    def status(self):
        with LOCK:
            return {'connected': bool(self.thread and self.thread.is_alive() and not self.stop_event.is_set()),
                    'id': self.sid, 'port': self.device, 'error': self.error, 'received': self.received,
                    'rejected': self.rejected, 'buffer_count': len(self.frames),
                    'synchronizing': not self.clock_tracker.ready, 'warmup_frames': self.warmup_frames}

    def board_status(self):
        with LOCK:
            return dict(self.board_info, networks=list(self.networks), event_seq=self.event_seq, last_event=self.last_event)

    def command(self, payload):
        if not self.status()['connected']:
            raise ValueError('USB 보드를 먼저 연결하세요.')
        if payload.get('cmd') not in ('status', 'scan', 'connect', 'disconnect'):
            raise ValueError('지원하지 않는 보드 명령입니다.')
        # Commands (including credentials) are never persisted in journals or logs.
        encoded = (json.dumps(payload, ensure_ascii=False) + '\n').encode('utf-8')
        if len(encoded) > 1000:
            raise ValueError('Wi-Fi 설정이 너무 깁니다.')
        with self.control_lock:
            self.port.write(encoded)

    def connect(self, device, baud):
        import serial
        from serial.tools import list_ports
        if device not in [p.device for p in list_ports.comports()]:
            raise ValueError('포트가 보이지 않습니다. 보드와 데이터 USB 케이블을 연결하세요.')
        if baud not in (115200, 460800, 921600):
            raise ValueError('지원하지 않는 전송 속도입니다.')
        if self.status()['connected']:
            raise ValueError('현재 연결을 먼저 종료하세요.')
        self.port = serial.Serial()
        self.port.port, self.port.baudrate, self.port.timeout = device, baud, 0.2
        self.port.write_timeout = 2
        self.port.dtr = self.port.rts = False
        self.port.open()
        with LOCK:
            self.sid = uuid.uuid4().hex
            self.frames.clear()
            self.received = self.rejected = 0
            self.error = ''
            self.board_info = {}
            self.networks = []
            self.last_event = ''
            self.event_seq += 1
            self.device = device
            self.header = None
            self.log_path = SESSIONS / f'{self.sid}.raw.jsonl'
            self.started_at = time.perf_counter()
            self.clock_tracker = LiveClock()
            self.warmup_frames = 0
            self.stop_event.clear()
        self.thread = threading.Thread(target=self.read_loop, daemon=True)
        self.thread.start()
        return self.status()

    def read_loop(self):
        start = self.started_at
        try:
            with self.log_path.open('a', encoding='utf-8') as journal:
                while not self.stop_event.is_set():
                    line = self.port.readline(65536).decode('utf-8', errors='replace').strip()
                    if not line:
                        continue
                    if line.startswith('{'):
                        try:
                            event = json.loads(line)
                            if isinstance(event, dict) and event.get('event') in ('status', 'scan'):
                                with LOCK:
                                    if event['event'] == 'scan':
                                        self.networks = event.get('networks', [])
                                    else:
                                        self.board_info.update(event)
                                    self.last_event = event['event']
                                    self.event_seq += 1
                                continue
                        except ValueError:
                            pass
                    if 'data' in line and '[' not in line:
                        fields = next(csv.reader([line]))
                        if 'data' in fields:
                            self.header = fields
                            continue
                    # Python 3.12 on Windows exposes a coarse GetTickCount64
                    # monotonic clock (~15 ms). perf_counter uses QPC and keeps
                    # successive CSI arrivals distinct even at 50+ Hz.
                    now = time.perf_counter() - start
                    frame = parse_csi_line(line, self.header, now, layout=board_layout(self.board_info))
                    if frame is None:
                        self.rejected += 1
                        continue
                    if frame.get('csi_profile') == 'soom_original_csv' and self.board_info.get('firmware') != 'SOOM-original-csv':
                        # Windows may deliver continuous CSI in USB bursts.
                        # Keep the device timeline; stale data is still cleared
                        # after .75 s and real device gaps reset the epoch.
                        self.clock_tracker.arrival_jitter = .75
                        with LOCK:
                            self.board_info.update(firmware='SOOM-original-csv',chip='esp32c6',role='receiver',
                                                   mode='espnow',state='connected',channel=11)
                            self.last_event='status'
                            self.event_seq+=1
                    frame['device_t'] = frame['t']
                    frame['arrival_t'] = now
                    mapped = self.clock_tracker.map_time(frame['device_t'], now)
                    if frame.get('csi_profile')=='c6_espnow_ht20_v1' and frame.get('gain_ready') is not True:
                        mapped = None
                    frame['accepted_live'] = mapped is not None
                    frame['stream_epoch'] = self.clock_tracker.epoch
                    frame['t'] = now if mapped is None else mapped
                    if mapped is None:
                        self.warmup_frames += 1
                    else:
                        with LOCK:
                            frame['seq'] = self.received
                            self.received += 1
                            self.frames.append(frame)
                    journal.write(json.dumps(frame, allow_nan=False) + '\n')
                    journal.flush()
        except Exception as exc:
            self.error = str(exc)
        finally:
            if self.port:
                self.port.close()
            with LOCK:
                snapshot = self.snapshot()
            if snapshot['frames']:
                write_json(SESSIONS / f'{self.sid}.json', snapshot)

    def disconnect(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=2)
        return self.status()


LIVE = LiveReader()


def saved_segments():
    return [upgrade_record(json.loads(p.read_text(encoding='utf-8'))) for p in sorted(SEGMENTS.glob('*.json'))]


def save_segment(payload):
    session = load_session(str(payload['source_id']))
    start, end = float(payload['start']), float(payload['end'])
    if end <= start:
        raise ValueError('끝 시간이 시작 시간보다 커야 합니다.')
    all_frames = session['frames']
    if not all_frames or start < all_frames[0]['t'] - 0.01 or end > all_frames[-1]['t'] + 0.01:
        raise ValueError('선택 구간이 현재 기록 범위를 벗어납니다. 오래된 라이브 기록은 원본 저널에 남아 있습니다.')
    selected = [f for f in all_frames if start <= f['t'] <= end]
    if len(selected) < 4:
        raise ValueError('4프레임 이상의 구간을 선택하세요.')
    label = str(payload.get('label', '')).strip()[:80]
    if not label or label == '미라벨':
        raise ValueError('저장할 행동 라벨을 선택하거나 직접 입력하세요.')
    group = str(payload.get('experiment_id', session['experiment_id'])).strip()[:120]
    if not group:
        raise ValueError('측정 세션 ID를 입력하세요.')
    # Segments cut from one source may never be split across train/test groups.
    for old in saved_segments():
        if old['source_id'] == session['id'] and old['experiment_id'] != group:
            raise ValueError('같은 원본 기록에는 기존 측정 세션 ID를 사용하세요: ' + old['experiment_id'])
    segment = {'id': uuid.uuid4().hex, 'label': label, 'start': start, 'end': end, 'frames': selected,
               'source_id': session['id'], 'source_name': session['name'], 'source_path': session['source_path'],
               'representation': session['representation'], 'experiment_id': group,
               'note': str(payload.get('note', ''))[:1500], 'processing': payload.get('processing', {}),
               'quality': session.get('quality', {}), 'created_at': datetime.now(timezone.utc).isoformat()}
    write_json(SEGMENTS / f"{segment['id']}.json", segment)
    return summary(segment)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'dist'), **kwargs)

    def log_message(self, *args):
        pass

    def send_json(self, value, status=200):
        content = json.dumps(value, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        url = urlparse(self.path)
        params = parse_qs(url.query)
        try:
            if url.path == '/api/health':
                return self.send_json({'app': 'csi-lab'})
            if url.path == '/api/sources':
                imports = []
                for p in SESSIONS.glob('*.json'):
                    record = json.loads(p.read_text(encoding='utf-8'))
                    if record.get('source_path') in ('import', 'live_serial'):
                        imports.append(summary(record))
                return self.send_json({'samples': [{k: v for k, v in x.items() if k != 'path'} for x in CATALOG], 'imports': imports})
            if url.path == '/api/source':
                return self.send_json(load_session(params['id'][0]))
            if url.path == '/api/ports':
                from serial.tools import list_ports
                return self.send_json({'ports': [{'device': p.device, 'name': p.description} for p in list_ports.comports()], 'live': LIVE.status()})
            if url.path == '/api/live':
                with LOCK:
                    after = int(params.get('after', ['-1'])[0])
                    frames = [f for f in LIVE.frames if f['seq'] > after]
                    return self.send_json({'status': LIVE.status(), 'session': summary(LIVE.snapshot()), 'frames': frames[-3000:]})
            if url.path == '/api/segments':
                return self.send_json([summary(x) for x in saved_segments()])
            if url.path == '/api/export':
                records = saved_segments()
                if not records:
                    raise ValueError('먼저 라벨 구간을 저장하세요.')
                buffer = io.BytesIO()
                with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
                    manifest = {'schema': 'csi-lab-dataset-v1', 'subcarrier_indices': __import__('core').SUBCARRIERS,
                                'iq_order': 'imaginary,real', 'segments': [summary(x) for x in records],
                                'split_group': 'experiment_id', 'warning': 'Source types must not be mixed; labels are user annotations.'}
                    archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2))
                    for record in records:
                        archive.writestr(f"segments/{record['id']}.json", json.dumps(record, ensure_ascii=False))
                        buf = io.StringIO(newline='')
                        writer = csv.writer(buf)
                        writer.writerow(['time_seconds', 'label', 'experiment_id', 'iq_json', 'amplitude_json', 'processed_signal'])
                        for f in record['frames']:
                            writer.writerow([f['t'], record['label'], record['experiment_id'], json.dumps(f.get('iq')), json.dumps(f.get('amp')), f.get('signal', '')])
                        archive.writestr(f"csv/{record['id']}.csv", buf.getvalue())
                body = buffer.getvalue()
                self.send_response(200)
                self.send_header('Content-Type', 'application/zip')
                self.send_header('Content-Disposition', 'attachment; filename="csi-dataset.zip"')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                return self.wfile.write(body)
            if url.path.startswith('/api/'):
                return self.send_json({'error': '없는 API 경로입니다.'}, 404)
            return super().do_GET()
        except Exception as exc:
            return self.send_json({'error': str(exc)}, 400)

    def do_POST(self):
        try:
            origin = self.headers.get('Origin')
            if origin and origin not in (f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'):
                return self.send_json({'error': '다른 사이트의 요청은 허용되지 않습니다.'}, 403)
            if not self.headers.get('Content-Type', '').startswith('application/json'):
                raise ValueError('JSON 요청이 필요합니다.')
            size = int(self.headers.get('Content-Length', '0'))
            if size <= 0 or size > 30_000_000:
                raise ValueError('파일 요청은 20 MB 이하로 제한됩니다.')
            payload = json.loads(self.rfile.read(size))
            route = urlparse(self.path).path
            if route == '/api/process':
                session = load_session(str(payload['source_id']))
                start, end = float(payload['start']), float(payload['end'])
                frames = [f for f in session['frames'] if start <= f['t'] <= end]
                return self.send_json(inspect_signal(frames, session['representation'], payload.get('options')))
            if route == '/api/import':
                blob = base64.b64decode(payload['content'], validate=True)
                if len(blob) > 20_000_000:
                    raise ValueError('20 MB 이하의 파일을 선택하세요.')
                name = Path(str(payload['name']).replace('\\', '/')).name
                session = make_session(blob, name, float(payload.get('rate', 60)))
                if len(session['frames']) > 60000:
                    raise ValueError('한 파일은 60,000프레임 이하로 나눠주세요.')
                write_json(SESSIONS / f"{session['id']}.json", session)
                with LOCK:
                    CACHE[session['id']] = session
                return self.send_json(session)
            if route == '/api/connect':
                return self.send_json(LIVE.connect(str(payload['port']), int(payload['baud'])))
            if route == '/api/disconnect':
                return self.send_json(LIVE.disconnect())
            if route == '/api/segment':
                return self.send_json(save_segment(payload), 201)
            if route == '/api/segment/update':
                sid = str(payload['id'])
                if not sid.isalnum() or len(sid) > 40:
                    raise ValueError('잘못된 구간 ID입니다.')
                file = SEGMENTS / f'{sid}.json'
                record = json.loads(file.read_text(encoding='utf-8'))
                label = str(payload['label']).strip()[:80]
                if not label:
                    raise ValueError('라벨을 입력하세요.')
                record['label'] = label
                record['note'] = str(payload.get('note', record['note']))[:1500]
                write_json(file, record)
                return self.send_json(summary(record))
            if route == '/api/train':
                records = [x for x in saved_segments() if x['representation'] == payload.get('representation')]
                if not records:
                    raise ValueError('선택한 유형의 라벨 데이터가 없습니다.')
                seconds = int(payload.get('window_seconds', 2))
                if seconds not in (2, 4, 8, 16):
                    raise ValueError('학습 창은 2, 4, 8, 16초 중 선택하세요.')
                model, result = train_baseline(records, seconds)
                import joblib
                model_id = uuid.uuid4().hex
                model_file = MODELS / f'{model_id}.joblib'
                joblib.dump({'model': model, 'metadata': result}, model_file)
                result['model_path'] = str(model_file)
                result['segment_ids'] = [x['id'] for x in records]
                write_json(MODELS / f'{model_id}.json', result)
                return self.send_json(result)
            return self.send_json({'error': '없는 API 경로입니다.'}, 404)
        except Exception as exc:
            return self.send_json({'error': str(exc)}, 400)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=5180)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'CSI Lab: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LIVE.disconnect()
        server.server_close()
