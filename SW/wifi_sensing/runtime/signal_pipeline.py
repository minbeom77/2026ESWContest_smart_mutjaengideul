"""One SOOM OnDevice window path for viewing, training, and recognition."""
import numpy as np
import pandas as pd
from soom_processing import preprocess_stages,PROFILE,RATE,CONFIG
from soom_engine import RealtimePreprocessor,preprocessor_dataframe,MODEL_TYPE


def _process(frames,representation,start,seconds,options=None):
    from core import signal_quality
    if seconds!=4:
        raise ValueError('SOOM 원본 모델 구조는 4초·240개 시점을 사용합니다.')
    recent=[f for f in frames if start-1e-9<=f['t']<=start+seconds+1e-9]
    if len(recent)<max(4,int(seconds*CONFIG['minimum_rate_hz'])):
        raise ValueError('4초 판단 구간에 수신 프레임이 부족합니다.')
    quality=signal_quality(recent,representation)
    if not quality['transport_ok']:
        raise ValueError('전처리할 수 없는 수신 기록: '+', '.join(quality['issues']))
    if recent[0]['t']-start>.04 or start+seconds-recent[-1]['t']>.04:
        raise ValueError('구간의 시작·끝에 새 신호가 부족합니다.')
    options=options or {}
    stages={k:options[k] for k in ('denoise','normalize','pca','lowpass','subcarrier') if k in options}
    processor=RealtimePreprocessor(pca_components=1,filter_ratio=.05)
    if representation=='raw_iq_52':
        csi=preprocessor_dataframe(recent)
        if all(stages.get(k,True) for k in ('denoise','normalize','pca','lowpass')):
            matrix=processor.run(csi,240)[:,None]
        else:
            resampled=processor._resample_multichannel_signal(csi,240)
            matrix=preprocess_stages(resampled,return_matrix=True,**stages)
    else:
        times=np.asarray([f['t'] for f in recent])
        matrix=np.interp(np.linspace(times[0],times[-1],240),times,[f['signal'] for f in recent])[:,None]
    grid=np.linspace(recent[0]['t'],recent[-1]['t'],240)
    return dict(time=grid.tolist(),signal=matrix[:,0].tolist(),components=matrix.tolist(),
                start=float(start),seconds=seconds,profile=PROFILE)


def signal_windows(frames,representation,seconds=4,options=None):
    if seconds!=4:
        raise ValueError('SOOM 처리 구간은 4초입니다.')
    if len(frames)<2: return []
    count=max(0,int(np.floor((frames[-1]['t']-frames[0]['t']+.025)/seconds)))
    windows=[]
    for i in range(count):
        try:
            windows.append(_process(frames,representation,frames[0]['t']+i*seconds,seconds,options))
        except ValueError:
            continue
    return windows


def latest_signal(frames,representation,seconds=4,options=None):
    if len(frames)<2 or frames[-1]['t']-frames[0]['t']<seconds-.025:
        raise ValueError(f'최종 전처리를 위해 새 신호 {seconds}초를 모으고 있습니다.')
    return _process(frames,representation,frames[-1]['t']-seconds,seconds,options)


def window_features(frames,representation,seconds=4):
    return [np.asarray(w['components'],dtype=np.float32).T for w in signal_windows(frames,representation,seconds)]


def inspect_signal(frames,representation,options=None):
    from core import signal_quality,SUBCARRIERS,estimate_rate
    options=options or {}; seconds=options.get('seconds',4)
    viewed=latest_signal(frames,representation,seconds,options)
    chosen=max(0,min(51,int(options.get('subcarrier',0)))) if representation=='raw_iq_52' else 0
    recent=[f for f in frames if f['t']>=viewed['start']-.025]
    times=np.asarray([f['t'] for f in recent])
    raw=np.vstack(preprocessor_dataframe(recent)['amplitude']) if representation=='raw_iq_52' else np.asarray([[f['signal']] for f in recent])
    return dict(time=viewed['time'],processed=viewed['signal'],components=viewed['components'],
                raw=np.interp(viewed['time'],times,raw[:,chosen]).tolist(),
                heatmap=raw.tolist() if representation=='raw_iq_52' else None,heat_time=times.tolist(),
                rate_hz=estimate_rate(recent),frame_count=len(recent),amplitude_min=float(raw.min()),amplitude_max=float(raw.max()),
                representation=representation,subcarrier_index=SUBCARRIERS[chosen] if representation=='raw_iq_52' else None,
                rssi=recent[-1].get('rssi'),signal_quality=signal_quality(recent,representation),profile=PROFILE)


def train_baseline(segments, seconds=4):
    from sklearn.metrics import balanced_accuracy_score, confusion_matrix
    from sklearn.model_selection import GroupShuffleSplit
    from soom_classifier import SoomClassifier
    representations = {s['representation'] for s in segments}
    if len(representations) != 1:
        raise ValueError('원본 CSI와 외부 전처리 기록을 섞어 학습할 수 없습니다.')
    x, y, groups, ids, starts = [], [], [], [], []
    discarded = 0
    for segment in segments:
        if segment.get('processing_error'):
            raise ValueError(segment['processing_error'])
        windows = signal_windows(segment['frames'], segment['representation'], seconds)
        possible = int(np.floor((segment['frames'][-1]['t']-segment['frames'][0]['t']+.025)/seconds))
        discarded += max(0,possible-len(windows))
        for window in windows:
            x.append(np.asarray(window['components'],dtype=np.float32).T)
            y.append(segment['label'])
            groups.append(segment.get('experiment_id') or segment['source_id'])
            ids.append(segment['id'])
            starts.append(window['start'])
    labels = sorted(set(y))
    if len(labels) < 2:
        raise ValueError(f'{seconds}초 이상의 서로 다른 행동 2종 이상이 필요합니다.')
    if any(len({g for g, label in zip(groups, y) if label == name}) < 3 for name in labels):
        raise ValueError('학습·검증·최종 평가를 분리하려면 행동별로 유효한 측정 회차 3개 이상이 필요합니다.')
    x, y, groups = np.asarray(x, dtype=np.float32), np.asarray(y), np.asarray(groups)
    split = None
    for development, test in GroupShuffleSplit(n_splits=100,test_size=.25,random_state=42).split(x,y,groups):
        if set(y[development]) != set(labels) or set(y[test]) != set(labels): continue
        for tr, va in GroupShuffleSplit(n_splits=100,test_size=.33,random_state=43).split(x[development],y[development],groups[development]):
            train,validation=development[tr],development[va]
            if set(y[train])==set(labels) and set(y[validation])==set(labels):
                split=train,validation,test; break
        if split is not None: break
    if split is None:
        raise ValueError('모든 행동을 포함하는 회차 분리가 필요합니다. 독립 측정을 더 추가하세요.')
    train, validation, test = split
    model = SoomClassifier().fit(x[train],y[train],validation=(x[validation],y[validation]))
    prediction = model.predict(x[test])
    split_names = np.full(len(x), 'test', dtype='<U10')
    split_names[train] = 'train'
    split_names[validation] = 'validation'
    model.training_input = dict(signals=x, labels=y, groups=groups, record_ids=np.asarray(ids),
                                starts=np.asarray(starts), split=split_names)
    result = dict(labels=labels, confusion_matrix=confusion_matrix(y[test], prediction, labels=labels).tolist(),
                  balanced_accuracy=float(balanced_accuracy_score(y[test], prediction)),
                  train_windows=len(train), validation_windows=len(validation),test_windows=len(test),train_groups=sorted(set(groups[train])),
                  validation_groups=sorted(set(groups[validation])),validation_accuracy=model.validation_accuracy,
                  test_groups=sorted(set(groups[test])), representation=next(iter(representations)),
                  window_seconds=seconds, input_length=round(seconds * RATE), features='final_multichannel_waveforms',
                  feature_profile=PROFILE, preprocessing=dict(CONFIG), resampling_hz=RATE,
                  model=MODEL_TYPE,epochs=model.epochs,best_epoch=model.best_epoch,seed=42,
                  input_channels=model.channels,discarded_windows=discarded,portable_max_error=model.portable_error,
                  score_threshold=model.threshold,score_margin=model.margin,temperature=model.temperature,
                  validation_history=model.validation_history, training_hyperparameters=model.hyperparameters,
                  training_loss=model.losses[-1], loss_history=model.losses)
    return model, result
