# MLOps Lab 1：Train, Track, Deploy and Autoscale an Iris Model

用 scikit-learn 訓練 iris 分類模型、以 MLflow 追蹤實驗、用 FastAPI 包成 API，部署到 kind（Kubernetes in Docker），並透過 HPA 依 CPU 自動擴展。

## 檔案說明
| 檔案 | 說明 |
|---|---|
| `train.py` | 訓練 RandomForest 模型，記錄參數與 accuracy 到 MLflow，輸出 `model.pkl` |
| `app.py` | FastAPI 服務：`POST /predict` 預測、`GET /healthz` 健康檢查 |
| `Dockerfile` | 打包 API 的映像檔 `iris-api:v1` |
| `deployment.yaml` | Kubernetes Deployment（含 resources 與 readinessProbe）及 Service |
| `model.pkl` | 訓練好的模型 |
| `mlflow-run.png` | MLflow run 截圖 |
| `hpa-scaling.png` | HPA 自動擴展截圖（replicas 1 → 4 → 5） |

## 環境
Windows 11、PowerShell、Docker Desktop、kind、kubectl、Python 3.11（scikit-learn 1.5.2、numpy 1.26.4）

## 執行步驟

### 1. 建立叢集
```powershell
kind create cluster --name mlops
```

### 2. 訓練模型並查看 MLflow
```powershell
py -3.11 train.py
py -3.11 -m mlflow ui   # 開啟 http://localhost:5000
```

### 3. 建立映像檔並載入叢集
```powershell
docker build -t iris-api:v1 .
kind load docker-image iris-api:v1 --name mlops
```

### 4. 部署
```powershell
kubectl apply -f deployment.yaml
kubectl get pods -w
```

### 5. 測試預測（另開一個視窗執行 port-forward）
```powershell
kubectl port-forward svc/iris-api 8080:80 --address 0.0.0.0
```
```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8080/predict -ContentType "application/json" -Body '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
# predictions: {0}
```

### 6. 自動擴展
```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'
kubectl autoscale deployment iris-api --cpu-percent=50 --min=1 --max=5
kubectl get hpa iris-api -w   # 另開視窗觀察
docker run --rm williamyeh/hey -z 60s -c 50 -m POST -T application/json -d '{\"instances\": [[5.1, 3.5, 1.4, 0.2]]}' http://host.docker.internal:8080/predict
```

## 與講義不同之處（Windows 調整）
| 講義 | 本實作 | 原因 |
|---|---|---|
| `port-forward ... &` | 另開視窗執行，並加 `--address 0.0.0.0` | PowerShell 不支援結尾 `&`；讓 Docker 容器內的 hey 能連到 |
| `curl -X POST ...` | `Invoke-RestMethod` | PowerShell 的 curl 是別名，參數格式不同 |
| `hey ...` | `docker run williamyeh/hey ...` 連 `host.docker.internal` | Windows 沒有 hey 執行檔 |
| （未列出） | 安裝 metrics-server 並加 `--kubelet-insecure-tls` | HPA 需要 metrics-server；kind 的 kubelet 憑證需此參數 |
| `log_model(clf, "model")` | `log_model(clf, name="model", skops_trusted_types=[...])` | MLflow 3.x 改用 `name`，且需明確信任 RandomForest 的型別 |
| `pip install ... scikit-learn joblib` | 固定 `scikit-learn==1.5.2 numpy==1.26.4` | 與訓練環境版本一致，確保 `model.pkl` 能正確載入 |

## 結果
- MLflow：n_estimators = 100，accuracy = 1.0
- HPA：壓力測試時 CPU 達 500%/50%，replicas 由 1 擴展到 5；測試結束後 CPU 回落
