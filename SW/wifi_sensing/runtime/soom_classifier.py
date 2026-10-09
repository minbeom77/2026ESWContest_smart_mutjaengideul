"""SOOM's unmodified Simple1DCNN, trained on user-defined labels."""
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader,TensorDataset
from soom_engine import Simple1DCNN,training_config as C,verify_vendor


class SoomClassifier:
    def fit(self,x,y,validation,epochs=None):
        verify_vendor()
        import random
        random.seed(C.SEED); np.random.seed(C.SEED); torch.manual_seed(C.SEED)
        torch.set_num_threads(2)
        self.classes_,encoded=np.unique(y,return_inverse=True)
        self.channels,self.input_length=x.shape[1:]
        if (self.channels,self.input_length)!=(1,240):
            raise ValueError('SOOM 학습 입력은 1개 신호·240개 시점이어야 합니다.')
        count=C.EPOCHS if epochs is None else epochs
        self.hyperparameters=dict(seed=C.SEED,epochs=count,batch_size=C.BATCH_SIZE,optimizer='AdamW',
                                  lr=C.LR,weight_decay=C.WEIGHT_DECAY,label_smoothing=C.LABEL_SMOOTHING,
                                  grad_clip=C.GRAD_CLIP,scheduler='CosineAnnealingLR',patience=C.PATIENCE,
                                  extra_input_scaling=False,label_source='selected_user_records')
        vx,vy=validation
        vencoded=np.asarray([list(self.classes_).index(v) for v in vy])
        tx=torch.from_numpy(np.asarray(x,dtype=np.float32)); ty=torch.from_numpy(encoded).long()
        tvx=torch.from_numpy(np.asarray(vx,dtype=np.float32)); tvy=torch.from_numpy(vencoded).long()
        loader=DataLoader(TensorDataset(tx,ty),batch_size=C.BATCH_SIZE,shuffle=True,num_workers=0)
        network=Simple1DCNN(num_classes=len(self.classes_),input_length=self.input_length)
        optimizer=torch.optim.AdamW(network.parameters(),lr=C.LR,weight_decay=C.WEIGHT_DECAY)
        criterion=nn.CrossEntropyLoss(label_smoothing=C.LABEL_SMOOTHING)
        scheduler=torch.optim.lr_scheduler.CosineAnnealingLR(optimizer,T_max=count)
        self.losses=[]; self.validation_history=[]; best=-1.
        for epoch in range(count):
            network.train(); total=0.
            for xb,yb in loader:
                optimizer.zero_grad(set_to_none=True)
                loss=criterion(network(xb),yb)
                if not torch.isfinite(loss): raise ValueError('학습 손실이 유효하지 않습니다.')
                loss.backward(); nn.utils.clip_grad_norm_(network.parameters(),C.GRAD_CLIP)
                optimizer.step(); total+=loss.item()*len(xb)
            network.eval()
            with torch.inference_mode():
                logits=network(tvx)
                score=float((logits.argmax(1)==tvy).float().mean())
                vloss=float(criterion(logits,tvy))
            scheduler.step(); self.losses.append(total/len(tx))
            self.validation_history.append(dict(epoch=epoch+1,accuracy=score,loss=vloss))
            if score>best:
                best=score; self.best_epoch=epoch+1
                self.weights={k:v.detach().cpu().numpy().copy() for k,v in network.state_dict().items()}
        self.epochs=count; self.validation_accuracy=best
        self.scale=np.ones((1,1,1),dtype=np.float32)
        self.temperature=1.; self.threshold=.6; self.margin=0.
        from cnn_runtime import forward
        network.load_state_dict({k:torch.from_numpy(v.copy()) for k,v in self.weights.items()})
        network.eval()
        with torch.inference_mode(): expected=network(tvx).numpy()
        actual=forward(self.weights,np.asarray(vx,dtype=np.float32))
        self.portable_error=float(np.max(np.abs(expected-actual)))
        if not np.allclose(expected,actual,atol=2e-4,rtol=2e-4):
            raise ValueError('SOOM 모델의 PC·내보내기 계산 결과가 다릅니다.')
        return self

    def predict_proba(self,x):
        values=np.asarray(x,dtype=np.float32)
        if values.ndim!=3 or tuple(values.shape[1:])!=(1,self.input_length):
            raise ValueError('학습 모델과 전처리 입력의 크기가 다릅니다.')
        network=Simple1DCNN(num_classes=len(self.classes_),input_length=self.input_length)
        network.load_state_dict({k:torch.from_numpy(v.copy()) for k,v in self.weights.items()})
        network.eval()
        with torch.inference_mode():
            return torch.softmax(network(torch.from_numpy(values)),dim=1).numpy()

    def predict(self,x):
        return self.classes_[np.argmax(self.predict_proba(x),axis=1)]
