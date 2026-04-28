# app/tests/test_app.py
import pytest
from app import app as flask_app

@pytest.fixture
def app():
    yield flask_app

@pytest.fixture
def client(app):
    return app.test_client()

def test_health_endpoint(client):
    """Test that the health endpoint returns 200 and healthy status"""
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()['status'] == 'healthy'

def test_dashboard_load(client):
    """Test that the main dashboard page loads successfully"""
    response = client.get('/')
    assert response.status_code == 200