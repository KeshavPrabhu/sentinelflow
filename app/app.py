# app/app.py
import os
import time
import uuid
import json
import requests
import redis
from flask import Flask, jsonify, render_template, request
from flask_sqlalchemy import SQLAlchemy
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST, Info

app = Flask(__name__)

# --- CONFIGURATION ---
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL', 'postgresql://pipelineops:pipelinepass@postgres:5432/pipelineops')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key')

db = SQLAlchemy(app)
# Redis for caching GitLab API and Prometheus calls
cache = redis.from_url(os.getenv('REDIS_URL', 'redis://redis:6379/0'), decode_responses=True)

APP_VERSION = os.getenv('APP_VERSION', '1.0.0')
ENV = os.getenv('APP_ENV', 'development')

# --- PROMETHEUS METRICS ---
REQUEST_COUNT = Counter('request_count_total', 'Total HTTP Requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('request_latency_seconds', 'HTTP Request Latency', ['endpoint'])
DEPLOY_GAUGE = Gauge('active_deployments_count', 'Total number of successful deployments recorded')
APP_INFO = Info('sentinelflow_app', 'Application Information')
APP_INFO.info({'version': APP_VERSION, 'env': ENV})

# --- DATABASE MODEL ---
class Deployment(db.Model):
    __tablename__ = 'deployments'
    id = db.Column(db.Integer, primary_key=True)
    version = db.Column(db.String(50), nullable=False)
    environment = db.Column(db.String(20), nullable=False)
    status = db.Column(db.String(20), nullable=False)
    deployed_by = db.Column(db.String(50))
    pipeline = db.Column(db.String(50))
    created_at = db.Column(db.DateTime, server_default=db.func.now())

# Initialize DB Tables
with app.app_context():
    db.create_all()

# --- MIDDLEWARE: STRUCTURED LOGGING & METRICS ---
@app.before_request
def start_timer():
    request.start_time = time.time()
    request.id = str(uuid.uuid4())

@app.after_request
def log_and_metrics(response):
    latency = time.time() - request.start_time
    # Prometheus Recording
    REQUEST_COUNT.labels(method=request.method, endpoint=request.path, status=response.status_code).inc()
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    
    # Structured JSON Logging (SRE Best Practice)
    log_data = {
        "timestamp": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        "request_id": request.id,
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "duration_ms": round(latency * 1000, 2),
        "version": APP_VERSION
    }
    print(json.dumps(log_data))
    return response

# --- ROUTES ---

@app.route('/')
def dashboard():
    return render_template('index.html', version=APP_VERSION, env=ENV)

@app.route('/health')
def health():
    """Liveness/Readiness probe endpoint for K8s/Pipelines"""
    health_report = {
        "status": "healthy",
        "version": APP_VERSION,
        "database": "up",
        "redis": "up"
    }
    try:
        db.session.execute(db.text('SELECT 1'))
    except Exception:
        health_report["database"] = "down"
        health_report["status"] = "unhealthy"
    
    try:
        cache.ping()
    except Exception:
        health_report["redis"] = "down"
        health_report["status"] = "unhealthy"
        
    return jsonify(health_report), 200 if health_report["status"] == "healthy" else 500

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/deployments', methods=['GET', 'POST'])
def deployments_api():
    if request.method == 'POST':
        data = request.get_json()
        new_deploy = Deployment(
            version=data.get('version'),
            environment=data.get('environment'),
            status=data.get('status'),
            deployed_by=data.get('deployed_by'),
            pipeline=data.get('pipeline', 'manual')
        )
        db.session.add(new_deploy)
        db.session.commit()
        DEPLOY_GAUGE.set(Deployment.query.count())
        return jsonify({"message": "Deployment recorded"}), 201
    
    deployments = Deployment.query.order_by(Deployment.created_at.desc()).limit(10).all()
    return jsonify([{
        "version": d.version, "env": d.environment, 
        "status": d.status, "by": d.deployed_by, 
        "time": d.created_at.isoformat()
    } for d in deployments])

@app.route('/api/pipeline-runs')
def pipeline_api():
    """Fetches GitLab Pipeline history (Cached)"""
    cached_pipelines = cache.get("pipeline_runs")
    if cached_pipelines:
        return jsonify(json.loads(cached_pipelines))
    
    # In a real setup, this would call GitLab API
    # requests.get(f"https://gitlab.com/api/v4/projects/{PID}/pipelines", headers=...)
    mock_data = [
        {"id": 1205, "status": "success", "ref": "main", "created_at": "2026-04-20T10:00:00Z"},
        {"id": 1204, "status": "failed", "ref": "feat-ui", "created_at": "2026-04-20T09:30:00Z"}
    ]
    cache.set("pipeline_runs", json.dumps(mock_data), ex=60)
    return jsonify(mock_data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)