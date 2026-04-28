# SentinelFlow — Hybrid CI/CD & SRE Automation Engine

[![GitLab CI](https://img.shields.io/badge/GitLab%20CI-Pass-green?logo=gitlab)](https://gitlab.com)
[![Jenkins](https://img.shields.io/badge/Jenkins-Automated-blue?logo=jenkins)](http://localhost:8080)
[![Kubernetes](https://img.shields.io/badge/K8s-Kind-blue?logo=kubernetes)](https://kind.sigs.k8s.io/)
[![Security](https://img.shields.io/badge/Trivy-Critical%20Gate-red?logo=trivy)](https://aquasec.github.io/trivy/)

**SentinelFlow** is a flagship DevOps project demonstrating a production-grade CI/CD ecosystem. It bridges the gap between cloud-native orchestration and bare-metal Linux automation, featuring automated rollbacks, forensic incident reporting, and real-time observability.

## 🚀 Architecture Flow
`Code Push` → `GitLab CI (Lint/Test/Build)` → `Trivy Scan` → `Deploy Staging` → `Smoke Test` → `[Manual Approval]` → `Deploy Prod`
*(On failure: Automated Rollback + Incident Report Generation)*

## 🛠 What This Project Demonstrates
| JD Requirement | Project Implementation | Key File |
| :--- | :--- | :--- |
| **Linux Administration** | Resource monitoring (CPU/Mem/Disk/DNS) | `scripts/system_health_check.sh` |
| **CI/CD Orchestration** | Hybrid GitLab CI & Jenkins integration | `.gitlab-ci.yml`, `Jenkinsfile` |
| **Containerization** | Multi-stage builds & non-root security | `app/Dockerfile` |
| **Kubernetes** | High Availability, Probes, & Rolling Updates | `k8s/deployment.yaml` |
| **Incident Management** | Automated RCA reports & forensic logging | `scripts/incident_report.sh` |
| **Observability** | Prometheus metrics & Golden Signals | `app/app.py` |
| **Automated Recovery** | Post-deploy smoke tests & auto-rollback | `scripts/rollback.sh` |

## 📦 Quick Start
1. **Prepare Environment:**
   ```bash
   cp .env.example .env
   make dev