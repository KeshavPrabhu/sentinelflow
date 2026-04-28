-- postgres/init.sql
CREATE TABLE IF NOT EXISTS deployments (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    environment VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    deployed_by VARCHAR(50),
    pipeline VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed initial data for the dashboard
INSERT INTO deployments (version, environment, status, deployed_by, pipeline) 
VALUES ('1.0.0-init', 'production', 'success', 'system', 'manual');