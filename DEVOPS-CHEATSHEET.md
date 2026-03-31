# 🚀 ShopEasy DevOps Cheat Sheet
> From Zero to Production | Gaurav Pal | March 2026
> Quick reference for interviews, revision, and rebuilding from scratch

---

## 📦 PHASE 1: DOCKER

### What is Docker?
Package your app + all its dependencies into a **container** that runs the same everywhere.
- **Image** = Recipe (read-only blueprint)
- **Container** = Running dish (instance of image)
- **Registry** = Storage for images (Docker Hub, ECR)

### Architecture
```
Your Code
    ↓
Dockerfile (instructions to build image)
    ↓
Docker Image (gauravpal1828/user-service:abc123)
    ↓
Docker Container (running app on port 3001)
```

### Key Files

**Dockerfile**
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app .
USER node
EXPOSE 3001
CMD ["node", "src/index.js"]
```

**docker-compose.yml** (local dev)
```yaml
version: '3.8'
services:
  user-service:
    build: ./services/user-service
    ports:
      - "3001:3001"
    env_file:
      - .env
```

### Essential Commands
```bash
# Build image
docker build -t gauravpal1828/user-service:latest .

# Run container
docker run -d -p 3001:3001 --name user-service gauravpal1828/user-service:latest

# Run with env file
docker run -d -p 3001:3001 --env-file .env --name user-service gauravpal1828/user-service:latest

# View running containers
docker ps

# View logs
docker logs -f user-service

# Stop & remove container
docker stop user-service && docker rm user-service

# Push to Docker Hub
docker login
docker push gauravpal1828/user-service:latest

# Pull from Docker Hub
docker pull gauravpal1828/user-service:latest

# Multi-stage build (smaller image)
docker build -t gauravpal1828/user-service:latest .
```

### Image Tagging Strategy
```
gauravpal1828/user-service:abc123def   ← SHA tag (immutable, use for deployments)
gauravpal1828/user-service:latest      ← Moving pointer (use for dev only)
```
**Rule:** Deploy with SHA. Never deploy with `latest` in production.

### Key Concepts
| Concept | One Line |
|---|---|
| Multi-stage build | Build in fat image, run in slim image (900MB → 150MB) |
| .dockerignore | Exclude node_modules, .env from image |
| --env-file | Inject config at runtime, not build time |
| Non-root user | Security: run as `node` user not root |
| HEALTHCHECK | Let orchestrators know if app is working |

### Interview Answers
**Q: How do you handle secrets in Docker?**
Never bake into image. Inject at runtime via `--env-file` or secrets manager.

**Q: Why multi-stage builds?**
Exclude build tools from production image. Smaller = faster, more secure.

---

## ⚙️ PHASE 2: CI/CD WITH GITHUB ACTIONS

### What is CI/CD?
- **CI (Continuous Integration):** Auto-test code on every push
- **CD (Continuous Deployment):** Auto-deploy after tests pass

### Architecture
```
git push origin develop
        ↓
GitHub detects push
        ↓
Spins up Ubuntu VM (GitHub-hosted runner)
        ↓
Runs workflow (.github/workflows/ci.yml)
        ↓
test-and-build job:
  ├── npm install
  ├── npm test
  ├── docker build → image:SHA
  └── docker push → Docker Hub
        ↓
deploy-dev job (only on develop branch):
  ├── Write PEM key from secret
  ├── SSH into EC2
  ├── docker pull image:SHA
  ├── docker stop old container
  └── docker run new container
```

### Complete ci.yml
```yaml
name: CI/CD - User Service

on:
  push:
    branches: [ main, develop, qa ]
  pull_request:
    branches: [ main, develop, qa ]

jobs:
  test-and-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - name: Install dependencies
        working-directory: ./services/user-service
        run: npm install
      - name: Run tests
        working-directory: ./services/user-service
        run: npm test
      - name: Login to Docker Hub
        if: github.event_name == 'push'
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: Build & Push Docker image
        if: github.event_name == 'push'
        working-directory: ./services/user-service
        run: |
          docker build -t gauravpal1828/user-service:${{ github.sha }} .
          docker build -t gauravpal1828/user-service:latest .
          docker push gauravpal1828/user-service:${{ github.sha }}
          docker push gauravpal1828/user-service:latest

  deploy-dev:
    needs: test-and-build
    if: github.ref == 'refs/heads/develop' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: DEV
    steps:
      - name: Deploy to DEV EC2
        run: |
          echo "${{ secrets.EC2_SSH_KEY }}" | base64 -d > key.pem
          chmod 400 key.pem
          ssh -i key.pem -o StrictHostKeyChecking=no ubuntu@${{ secrets.EC2_DEV_IP }} "
            docker pull gauravpal1828/user-service:${{ github.sha }} &&
            docker stop user-service || true &&
            docker rm user-service || true &&
            docker run -d -p 3001:3001 --name user-service gauravpal1828/user-service:${{ github.sha }}
          "

  deploy-qa:
    needs: test-and-build
    if: github.ref == 'refs/heads/qa' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: QA
    steps:
      - name: Deploy to QA
        run: echo "Deploy to QA EC2 (same pattern as DEV)"

  deploy-prod:
    needs: test-and-build
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: PROD  # ← requires manual approval
    steps:
      - name: Deploy to PROD
        run: echo "Deploy to PROD EC2 (same pattern as DEV)"
```

### GitHub Secrets Setup
| Secret | Where | Value |
|---|---|---|
| DOCKERHUB_USERNAME | Repository | gauravpal1828 |
| DOCKERHUB_TOKEN | Repository | Docker Hub access token |
| EC2_SSH_KEY | Repository | base64-encoded PEM key |
| EC2_DEV_IP | Repository | EC2 public IP |
| DB_HOST | Environment (DEV/QA/PROD) | Database host |

### Encode PEM key for GitHub Secret
```bash
# Mac
base64 -i ~/Downloads/shopeasy-key.pem | pbcopy

# Linux
base64 ~/Downloads/shopeasy-key.pem
# Copy output → paste into EC2_SSH_KEY secret
```

### Branch → Environment Mapping
```
develop → DEV environment (auto-deploy)
qa      → QA environment (auto-deploy)
main    → PROD environment (manual approval required)
```

### Common Issues & Fixes
| Error | Cause | Fix |
|---|---|---|
| `Connection timed out` on port 22 | Security group blocks GitHub runner IP | Change port 22 source to 0.0.0.0/0 |
| `error in libcrypto` | PEM newlines corrupted in GitHub Secrets | Store as base64, decode with `base64 -d` |
| `docker: command not found` | Docker not installed on EC2 | Add user-data script or install manually |
| Tests pass locally, fail in CI | Missing env vars or wrong Node version | Add env vars to workflow, match Node version |

### Interview Answers
**Q: What happens when you push code?**
GitHub detects push → spins up Ubuntu runner → runs workflow → tests → builds image with SHA tag → pushes to Docker Hub → SSHs into EC2 → pulls new image → restarts container. Zero manual steps.

**Q: Why SHA tags not latest for deployment?**
SHA is immutable — always points to exact same build. `latest` moves on every push — unreliable, can't rollback precisely.

**Q: How do you rollback?**
Every build has SHA tag in Docker Hub. SSH into EC2, `docker run` with previous SHA. Or revert git commit and push — CI/CD deploys previous version automatically.

---

## ☁️ PHASE 3: AWS INFRASTRUCTURE

### AWS Account Setup (Day 22)
1. Create AWS account (free tier)
2. Enable MFA on root account
3. Create IAM user `shopeasy-admin` with AdministratorAccess
4. Enable billing access for IAM users (from root account)
5. Create billing alarm in **us-east-1** (CloudWatch billing only works here)

**⚠️ Critical:** Billing metrics ONLY available in us-east-1 regardless of your working region.

```
Root Account (never use for daily work)
    └── IAM User: shopeasy-admin (use this for everything)
```

---

### VPC & Networking (Day 23)

#### What is VPC?
Your private network inside AWS. Like your own isolated data center.

#### Architecture
```
shopeasy-vpc (10.0.0.0/16)
├── Public Subnet 1 (10.0.1.0/24) ap-south-1a  ← EC2 lives here
├── Public Subnet 2 (10.0.2.0/24) ap-south-1b  ← ALB uses this too
├── Private Subnet 1 (10.0.3.0/24) ap-south-1a ← RDS will live here
└── Private Subnet 2 (10.0.4.0/24) ap-south-1b ← RDS Multi-AZ

Internet Gateway (shopeasy-igw)
    ↑ attached to VPC

Public Route Table (shopeasy-public-rt)
    0.0.0.0/0 → shopeasy-igw   ← THIS is what makes subnet "public"
    associated with public-1 + public-2
```

**Key rule:** Public vs private subnet = route table rule. Public has `0.0.0.0/0 → IGW`. Private does not.

#### Resources Created
| Resource | Name | Value |
|---|---|---|
| VPC | shopeasy-vpc | vpc-0e62f617f94378221, 10.0.0.0/16 |
| Public Subnet 1 | shopeasy-public-1 | subnet-05ab0148d007103d4, 10.0.1.0/24, ap-south-1a |
| Public Subnet 2 | shopeasy-public-2 | subnet-0eef3bebbb62c887f, 10.0.2.0/24, ap-south-1b |
| Private Subnet 1 | shopeasy-private-1 | subnet-0fb125248a83d523b, 10.0.3.0/24, ap-south-1a |
| Private Subnet 2 | shopeasy-private-2 | subnet-0c74a24863fdd87ce, 10.0.4.0/24, ap-south-1b |
| Internet Gateway | shopeasy-igw | igw-06edbd2da224399e5 |
| Route Table | shopeasy-public-rt | rtb-0767a998fbe2d843b |

#### Security Groups
```
shopeasy-ec2-sg (EC2 firewall)
├── Inbound: Port 22  → 0.0.0.0/0       (SSH — restrict in production)
├── Inbound: Port 3001 → shopeasy-alb-sg (app — only ALB can reach it)
├── Inbound: Port 80  → 0.0.0.0/0       (HTTP)
└── Outbound: All → 0.0.0.0/0

shopeasy-alb-sg (ALB firewall)
├── Inbound: Port 80  → 0.0.0.0/0  (HTTP from internet)
├── Inbound: Port 443 → 0.0.0.0/0  (HTTPS from internet)
└── Outbound: All → 0.0.0.0/0
```

**⚠️ Security rule:** EC2 port 3001 should only allow traffic from `shopeasy-alb-sg`, not from internet directly.

#### Interview Answers
**Q: What's the difference between security group and NACL?**
Security group = stateful firewall at instance level. NACL = stateless firewall at subnet level. Security groups are easier and sufficient for most use cases.

**Q: Why public and private subnets?**
EC2 (web servers) in public — need to be reachable from internet. RDS (databases) in private — should NEVER be reachable from internet, only from EC2 internally.

---

### EC2 (Day 24)

#### What is EC2?
Virtual machine in AWS. You pick OS, size, and it runs 24/7.

#### Launch Config (use every time)
| Field | Value |
|---|---|
| Name | shopeasy-user-service-dev |
| AMI | Ubuntu 24.04 LTS |
| Instance type | t2.micro (free tier) |
| Key pair | shopeasy-key (NEVER recreate, keep .pem safe) |
| VPC | shopeasy-vpc |
| Subnet | shopeasy-public-1 |
| Auto-assign public IP | ENABLE |
| Security group | shopeasy-ec2-sg |

#### User Data Script (auto-installs Docker on boot)
```bash
#!/bin/bash
apt-get update -y
apt-get install -y docker.io
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu
```
Paste this in Advanced Details → User data when launching EC2.

#### SSH into EC2
```bash
ssh -i ~/Downloads/shopeasy-key.pem ubuntu@[EC2-PUBLIC-IP]

# Fix docker permission for current session
newgrp docker

# Verify docker
docker --version

# Run user-service manually
docker run -d -p 3001:3001 --name user-service gauravpal1828/user-service:latest

# Verify
curl http://localhost:3001/health
```

#### Common Issues
| Error | Fix |
|---|---|
| `Permission denied (publickey)` | Wrong path to .pem file. Run `find ~ -name "shopeasy-key.pem"` |
| `Permission denied` on docker commands | Run `newgrp docker` to reload group |
| `chmod 400` required | SSH rejects keys with open permissions. Always `chmod 400 key.pem` |

#### Key Learning
EC2 public IP changes on stop/start. Fixed by ALB (stable DNS) or Elastic IP.

---

### ALB - Application Load Balancer (Day 26)

#### What is ALB?
Sits in front of your servers. Single stable entry point. Handles HTTPS. Routes traffic.

#### Architecture
```
Internet (port 80/443)
        ↓
[shopeasy-alb-sg] port 80, 443 open
        ↓
ALB: shopeasy-alb-dev
DNS: shopeasy-alb-dev-1882740143.ap-south-1.elb.amazonaws.com
        ↓
Target Group: shopeasy-tg-dev
(health check: GET /health every 30s)
        ↓
[shopeasy-ec2-sg] port 3001 open ONLY from shopeasy-alb-sg
        ↓
EC2 → Docker → user-service:3001
```

#### Three Components
1. **Target Group** — list of EC2s + which port to send traffic to + health check config
2. **ALB** — the load balancer itself, needs 2 subnets in different AZs
3. **Listener** — rule: "traffic on port 80 → forward to target group"

#### Step-by-Step: Create Target Group
1. EC2 → Target Groups → Create target group
2. Target type: Instances
3. Name: `shopeasy-tg-dev`
4. Protocol: HTTP, Port: 3001
5. VPC: shopeasy-vpc
6. Health check path: `/health`
7. Next → select EC2 instance → Include as pending → Create

#### Step-by-Step: Create ALB
1. EC2 → Load Balancers → Create → Application Load Balancer
2. Name: `shopeasy-alb-dev`
3. Scheme: Internet-facing
4. VPC: shopeasy-vpc
5. Subnets: select shopeasy-public-1 (ap-south-1a) + shopeasy-public-2 (ap-south-1b)
6. Security group: shopeasy-alb-sg (**not** ec2-sg)
7. Listener: HTTP:80 → forward to shopeasy-tg-dev
8. Create

#### Step-by-Step: Lock Down EC2 Security Group
After ALB is created:
- Go to shopeasy-ec2-sg → Edit inbound rules
- Delete port 3001 rule with source 0.0.0.0/0
- Add new: Custom TCP, port 3001, source = shopeasy-alb-sg
- Save

This ensures internet can't bypass ALB and hit EC2 directly.

#### Common Issues
| Issue | Fix |
|---|---|
| ALB security group not showing in dropdown | Created in wrong VPC. Recreate in shopeasy-vpc |
| Target showing "Unhealthy" | Container not running on EC2, or /health endpoint not responding |
| 502 Bad Gateway | ALB can't reach EC2. Check security group rules |

#### ALB Resources
| Resource | Value |
|---|---|
| ALB Name | shopeasy-alb-dev |
| DNS | shopeasy-alb-dev-1882740143.ap-south-1.elb.amazonaws.com |
| ALB SG | shopeasy-alb-sg (sg-0a8164a104217213b) |

#### Why ALB over alternatives?
| Option | Problem |
|---|---|
| Raw EC2 IP | Changes on restart, no HTTPS, no health checks |
| Elastic IP | Fixed IP but no HTTPS, no health checks, no routing |
| ALB | Fixed DNS, HTTPS, health checks, path routing, scales across multiple EC2s |

#### Interview Answers
**Q: Why two separate security groups for ALB and EC2?**
Defence in depth. If someone finds EC2 IP, they still can't access port 3001 — it only allows traffic from ALB security group. All traffic must go through ALB where you can add WAF, rate limiting, logging.

**Q: Why does ALB need two subnets?**
ALB spans multiple Availability Zones for high availability. If ap-south-1a goes down, ALB still works from ap-south-1b.

**Q: What happens if EC2 goes down?**
ALB health check detects failure → stops routing traffic to that instance. With multiple instances, others take over. With one instance (dev), users get 502.

---

## 🔑 MASTER REFERENCE

### AWS Resources (ap-south-1)
| Resource | Name | ID |
|---|---|---|
| VPC | shopeasy-vpc | vpc-0e62f617f94378221 |
| Public Subnet 1 | shopeasy-public-1 | subnet-05ab0148d007103d4 |
| Public Subnet 2 | shopeasy-public-2 | subnet-0eef3bebbb62c887f |
| Private Subnet 1 | shopeasy-private-1 | subnet-0fb125248a83d523b |
| Private Subnet 2 | shopeasy-private-2 | subnet-0c74a24863fdd87ce |
| IGW | shopeasy-igw | igw-06edbd2da224399e5 |
| Route Table | shopeasy-public-rt | rtb-0767a998fbe2d843b |
| EC2 SG | shopeasy-ec2-sg | sg-06510dfcca821d6f4 |
| ALB SG | shopeasy-alb-sg | sg-0a8164a104217213b |
| ALB | shopeasy-alb-dev | DNS above |
| Target Group | shopeasy-tg-dev | port 3001 |

### GitHub & Docker Hub
| Resource | Value |
|---|---|
| GitHub Repo | github.com/kratos619/shopeasy-microservices |
| Docker Hub | hub.docker.com/r/gauravpal1828/user-service |
| Branches | main (PROD), qa (QA), develop (DEV) |

### Rebuild EC2 Checklist (when terminated)
- [ ] Launch EC2 with exact config above + user-data script
- [ ] Note new public IP
- [ ] SSH in: `ssh -i ~/Downloads/shopeasy-key.pem ubuntu@[NEW-IP]`
- [ ] `newgrp docker && docker ps` (verify Docker installed)
- [ ] Update `EC2_DEV_IP` GitHub Secret with new IP
- [ ] Register new EC2 in target group `shopeasy-tg-dev`
- [ ] Push any commit to develop → verify auto-deployment works

### Delete/Recreate ALB Checklist
**Delete order:** ALB → Target Group
**Recreate order:** Target Group → ALB
- Takes ~2 min to provision
- DNS name changes each time you recreate — update anywhere it's referenced

---

## 📋 COMPLETE FLOW DIAGRAM

```
DEVELOPER PUSHES CODE:

git push origin develop
        │
        ▼
┌─────────────────────────────────────┐
│     GitHub Actions Runner (VM)       │
│                                     │
│  1. git checkout code               │
│  2. npm install                     │
│  3. npm test ──── FAIL? Stop here   │
│  4. docker build :SHA               │
│  5. docker push → Docker Hub        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│        deploy-dev job               │
│                                     │
│  1. Decode base64 PEM key           │
│  2. SSH → EC2 (65.2.149.139)        │
│  3. docker pull :SHA                │
│  4. docker stop old container       │
│  5. docker run new container        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  EC2: shopeasy-user-service-dev     │
│  Container running :SHA on port 3001│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  ALB: shopeasy-alb-dev              │
│  DNS: shopeasy-alb-dev-xxx.elb.com  │
│  Health check: GET /health ✅        │
└──────────────┬──────────────────────┘
               │
               ▼
        USER BROWSER
  http://shopeasy-alb-dev-xxx.elb.com/health
  {"status":"healthy","service":"user-service"}
```

---

## ⏭️ WHAT'S NEXT

| Day | Topic | Goal |
|---|---|---|
| 26 (current) | ALB + HTTPS | Add SSL certificate via ACM |
| 28 | Route53 | Point domain to ALB |
| 29-30 | RDS MySQL | Real database in private subnet |
| 31-33 | ECR | Private image registry on AWS |
| Terraform | IaC | Entire infra as code |
| Kubernetes | EKS | Container orchestration |