"""SOOM OnDevice stages in the original order. Toggles affect previews only."""
import numpy as np
from soom_engine import PROFILE,upstream_signal
RATE=60
COMPONENTS=1
CONFIG=dict(profile=PROFILE,resampling_hz=60,normalization='channel_standardization_after_dwt',
            channel_mapping='soom_original_52',dwt='db4',dwt_level='automatic',
            dwt_threshold='universal_per_level_0.85',pca_components=1,pca_fit='each_complete_window',
            lowpass='original_fft_mask',filter_ratio=.05,window_seconds=4,input_length=240,
            max_interpolation_gap_s=.5,minimum_rate_hz=20.)


def preprocess(amplitude):
    return preprocess_stages(amplitude,return_matrix=True)


def preprocess_stages(amplitude,denoise=True,pca=True,lowpass=True,subcarrier=0,
                      return_matrix=False,component=0,normalize=True):
    data=np.asarray(amplitude,dtype=float)
    if data.ndim!=2 or data.shape[1]!=52 or len(data)<2 or not np.isfinite(data).all():
        raise ValueError('SOOM 전처리에는 52개 채널 진폭이 필요합니다.')
    if denoise:
        data=upstream_signal.dwt_denoise_matrix(data)
    if normalize:
        data=upstream_signal.standardize_matrix(data)
    if pca:
        data=upstream_signal.pca_52_subcarriers(data,n_components=1)
    else:
        data=data[:,[max(0,min(51,int(subcarrier)))]]
    if lowpass:
        data=upstream_signal.fft_lowpass_filter(data,cutoff_freq_ratio=.05)[:,None]
    return data if return_matrix else data[:,0]
