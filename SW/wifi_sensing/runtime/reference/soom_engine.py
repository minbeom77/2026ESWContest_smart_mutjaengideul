"""SOOM original functions and architecture; labels are always supplied by the user."""
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


def preprocessor_dataframe(frames):
    raw=raw_dataframe(frames)
    amp,_=amp_phase_from_csi(raw,column='data')
    df=pd.DataFrame({'timestamp':raw.index,'amplitude':[row for row in amp]})
    df['timestamp']=df['timestamp'].astype(np.int64)/1e9
    return df
