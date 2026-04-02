web: sh -c "python manage.py migrate && python manage.py collectstatic --noinput && gunicorn saleor.wsgi:application --bind 0.0.0.0:8000"
