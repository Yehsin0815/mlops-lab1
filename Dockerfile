FROM python:3.12-slim
WORKDIR /app
RUN pip install fastapi uvicorn scikit-learn==1.5.2 numpy==1.26.4 joblib
COPY model.pkl app.py ./
CMD uvicorn app:app --host 0.0.0.0 --port 8080
