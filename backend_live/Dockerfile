FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY . /app
ENV CENPOP_PATH=/app/CenPop2020_Mean_CO.txt
ENV PORT=10000
CMD ["uvicorn","main_cenpop:app","--host","0.0.0.0","--port","10000","--workers","2","--timeout-keep-alive","75"]
