"""SOOM processing with a numerically equivalent I/Q input conversion.

The upstream signal stages and CNN are unchanged. The original adapter is
preserved in reference/soom_engine.py; LOCAL_MODIFICATIONS.json records hashes.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
import pandas as pd
from soom_upstream.utils.rt_preprocess import RealtimePreprocessor
from soom_upstream.utils import signal_processing as upstream_signal
from soom_upstream.utils.extract import amp_phase_from_csi
from soom_upstream.training_classifier import Simple1DCNN
from soom_upstream import training_config

PROFILE = 'soom_ondevice_original_52_dwt_standardize_pca1_fft_v1'
MODEL_TYPE = 'SOOM_CNN_USER_LABELS_v1'
UPSTREAM = Path(__file__).resolve().parent / 'soom_upstream'


def verify_vendor():
    manifest = json.loads((UPSTREAM/'manifest.json').read_text(encoding='utf-8'))
    for name,expected in manifest['files'].items():
        if hashlib.sha256((UPSTREAM/name).read_bytes()).hexdigest()!=expected:
            raise ValueError('SOOM 원본 소스 해시 불일치: '+name)
    return manifest


def verify_runtime():
    """Verify the preserved laptop snapshot and explicitly recorded changes."""
    root = Path(__file__).resolve().parent
    baseline = json.loads((root / 'LOCAL_SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    modifications = json.loads((root / 'LOCAL_MODIFICATIONS.json').read_text(encoding='utf-8'))
    changed = modifications['files']
    if not isinstance(changed, dict) or not set(changed).issubset(baseline['files']):
        raise ValueError('런타임 변경 명세가 올바르지 않습니다.')
    for name, expected in baseline['files'].items():
        active = root / name
        if name in changed:
            record = changed[name]
            reference = (root / record['reference']).resolve()
            if (not reference.is_relative_to(root.resolve())
                    or record['original_sha256'] != expected
                    or hashlib.sha256(reference.read_bytes()).hexdigest() != expected):
                raise ValueError('보존된 원본 소스 해시 불일치: ' + name)
            expected = record['active_sha256']
        if hashlib.sha256(active.read_bytes()).hexdigest() != expected:
            raise ValueError('실행용 소스 해시 불일치: ' + name)
    verify_vendor()
    return dict(baseline_files=len(baseline['files']), modified_files=len(changed),
                implementation_revision=modifications['implementation_revision'])


def raw_dataframe(frames):
    if not frames or any(not isinstance(f.get('iq'),list) or len(f['iq'])!=128 for f in frames):
        raise ValueError('SOOM 과정에는 프레임당 128개의 원본 I/Q가 필요합니다.')
    times=np.asarray([f.get('device_t',f['t']) for f in frames],dtype=float)
    if not np.isfinite(times).all() or np.any(np.diff(times)<=0):
        raise ValueError('CSI 시간 순서가 올바르지 않습니다.')
    iq=np.asarray([f['iq'] for f in frames])
    if not np.isfinite(iq).all() or np.any(iq!=np.floor(iq)) or np.any(iq < -128) or np.any(iq > 127):
        raise ValueError('CSI I/Q 값이 올바르지 않습니다.')
    df=pd.DataFrame({'real_timestamp':times,'data':[json.dumps(f['iq'],separators=(',',':')) for f in frames]})
    df.index=pd.to_datetime(times,unit='s')
    return df


def _reference_preprocessor_dataframe(frames):
    """Retain the original conversion for unusual legacy Python values."""
    raw=raw_dataframe(frames)
    amp,_=amp_phase_from_csi(raw,column='data')
    df=pd.DataFrame({'timestamp':raw.index,'amplitude':[row for row in amp]})
    df['timestamp']=df['timestamp'].astype(np.int64)/1e9
    return df


def preprocessor_dataframe_from_iq(iq, timestamps):
    """Convert numeric N-by-128 I/Q directly to the original 52 amplitudes.

    Integer conversion, carrier selection, and nanosecond timestamp rounding
    deliberately match the original JSON/AST adapter. No input is modified.
    """
    times = np.asarray(timestamps, dtype=float)
    if (times.ndim != 1 or not len(times) or not np.isfinite(times).all()
            or np.any(np.diff(times) <= 0)):
        raise ValueError('CSI 시간 순서가 올바르지 않습니다.')
    values = np.asarray(iq)
    if values.ndim != 2 or values.shape != (len(times), 128):
        raise ValueError('SOOM 과정에는 프레임당 128개의 원본 I/Q가 필요합니다.')
    if (values.dtype.kind not in 'iuf' or not np.isfinite(values).all()
            or np.any(values != np.floor(values))
            or np.any(values < -128) or np.any(values > 127)):
        raise ValueError('CSI I/Q 값이 올바르지 않습니다.')
    # The upstream extractor casts both I and Q to int64 before np.hypot.
    values = values.astype(np.int64, copy=False)
    amplitude = np.hypot(values[:, ::2], values[:, 1::2])
    amplitude = np.concatenate((amplitude[:, 6:32], amplitude[:, 33:59]), axis=1)
    df = pd.DataFrame({
        'timestamp': pd.to_datetime(times, unit='s'),
        'amplitude': [row for row in amplitude],
    })
    df['timestamp'] = df['timestamp'].astype(np.int64) / 1e9
    return df


def preprocessor_dataframe(frames):
    """Shared numeric adapter for preview, training, and portable inference."""
    if not frames or any(
            not isinstance(frame.get('iq'), list) or len(frame['iq']) != 128
            for frame in frames):
        return _reference_preprocessor_dataframe(frames)
    rows = [frame['iq'] for frame in frames]
    # bool serializes as JSON true/false, which the old AST reader rejects.
    # NumPy/custom scalar serialization also differs: preserve that behavior.
    if not all(type(value) in (int, float) for row in rows for value in row):
        return _reference_preprocessor_dataframe(frames)
    timestamps = [frame.get('device_t', frame['t']) for frame in frames]
    try:
        return preprocessor_dataframe_from_iq(rows, timestamps)
    except (TypeError, ValueError, OverflowError):
        # Preserve the original exception type/order for malformed records,
        # including oversized integers that NumPy represents as objects.
        return _reference_preprocessor_dataframe(frames)
