# How to Clean Up All Resources

The cleanup job destroys ALL AWS resources created by the deployment workflow.

---

## Steps to Run Cleanup

### Step 1: Go to GitHub Actions
Open your browser and go to:
```
https://github.com/Olisaemeka111/ansible_project_2025/actions
```

### Step 2: Select the Workflow
In the left sidebar, click **"Deploy 3-Tier Infrastructure"**

### Step 3: Click "Run workflow"
On the right side of the page, you'll see a **"Run workflow"** dropdown button.
Click it.

### Step 4: Select "cleanup"
- Branch: `main`
- Action to perform: change from `deploy` to **`cleanup`**

### Step 5: Click the green "Run workflow" button
The cleanup job will start running.

---

## What Gets Deleted (in order)

| Step | Resource | Details |
|------|----------|---------|
| 1 | ALB | Load balancer listeners, ALB, target group |
| 2 | EC2 Instances | All 30 servers + control node (waits for termination) |
| 3 | Security Groups | Revokes all rules first, then deletes 5 SGs |
| 4 | NAT Gateway | Deletes NAT GW + releases Elastic IP |
| 5 | Internet Gateway | Detaches from VPC, then deletes |
| 6 | Subnets | All 6 subnets (3 public + 3 private) |
| 7 | Route Tables | Disassociates, then deletes custom route tables |
| 8 | VPC | Deletes the VPC itself |
| 9 | SSH Key Pair | Removes from EC2 and from S3 bucket |

## What is Preserved
- **S3 bucket**: `bus-terminal-deploy-156041437006` (for future deployments)
- **IAM role**: `bus-terminal-ec2-ssm` (for future deployments)
- **GitHub Secrets**: AWS credentials remain configured

## Estimated Cleanup Time
~5-10 minutes

## Important Notes
- Cleanup only runs via **manual dispatch** — pushing code will NOT trigger it
- You cannot run cleanup by clicking "Re-run all jobs" on a push-triggered run
- After cleanup, push to `main` to redeploy everything from scratch

## To Redeploy After Cleanup
Simply push any change to `main`, or manually run the workflow with `deploy` selected.
