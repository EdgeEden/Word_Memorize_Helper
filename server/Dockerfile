FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY main.py database.py models.py ./

# Create data directory for SQLite persistence and dist directory for release packages
RUN mkdir -p data dist

EXPOSE 25642

ENV PORT=25642

CMD ["python", "main.py"]
