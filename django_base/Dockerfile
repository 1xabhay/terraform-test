FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN python -m pip install --no-cache-dir "Django==6.0.3" "psycopg[binary]>=3.2,<4" "redis>=5,<7"

COPY manage.py /app/
COPY django_base /app/django_base/

EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate && python manage.py runserver 0.0.0.0:8000"]
