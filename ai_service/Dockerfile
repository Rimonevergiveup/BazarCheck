FROM python:3.11-slim

# Do not buffer stdout, and do not write .pyc files into the image.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install dependencies first so this layer caches independently of source edits.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create the unprivileged runtime user.
#
# The previous version used BusyBox/Alpine flags (`addgroup -g`, `adduser -D`)
# on a Debian base image. Both are ambiguous under Debian's adduser, so the RUN
# layer exited non-zero and `docker build` failed outright. These are the
# Debian long-form equivalents.
RUN addgroup --system --gid 1001 appgroup \
 && adduser  --system --uid 1001 --ingroup appgroup --disabled-password --gecos "" appuser

COPY --chown=appuser:appgroup . .

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status==200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
