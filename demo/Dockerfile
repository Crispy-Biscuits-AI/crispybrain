FROM python:3.12-slim

WORKDIR /app

COPY demo /app/demo
COPY assets /app/assets

EXPOSE 8787

CMD ["python", "-m", "demo.server"]
