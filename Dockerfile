FROM python:3.13-slim
LABEL maintainer="ethanopp"

# Install GCC to build wheels natively for Numpy/Pandas if pre-compiled binaries are sparse on Py3.13
RUN apt-get update && apt-get install -y gcc default-libmysqlclient-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pin Gunicorn manually since it was abstracted by Meinheld previously
RUN pip install -U pip && pip install --no-cache-dir gunicorn

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONPATH=/app/src
ENV NGINX_WORKER_PROCESSES=auto

STOPSIGNAL SIGINT

CMD ["gunicorn", "-c", "gunicorn_conf.py", "fitly.app:server"]
