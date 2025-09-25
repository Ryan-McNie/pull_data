## PRE-REQUISITES
Have Docker Installed:
```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```
```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
Create Docker group and add current user to docker group to remove sudo requirement:
```bash
sudo groupadd docker || true
sudo usermod -aG docker $USER
newgrp docker
sudo systemctl restart docker
```


## SETUP

Pull from Git:
```bash
git clone https://github.com/Ryan-McNie/pull_data.git
```
Build the docker image:
```bash
docker build -t pull_data .
```

## USAGE

### Date Formats

You can specify the date in any of the following formats:

- `YYYYMMDD` – e.g. `20250607`
- `YYMMDD` – e.g. `250607`
- `YYYYDOY` – e.g. `2025151`
- `DOY` – e.g. `151` (uses current year)

### 1. Pull SBAS Data

Pulls SBAS data from S3. Checks for completeness and selects the most complete dataset.  
**SIS priority order:** Novatel → Septentrio → GMV  
**INT priority order:** Uralla → Awarua → GMV  
Includes the last 15 minutes from the previous day.

**Usage:**
```bash
./run.sh pull_sbas <date>
```
**Example:**
```bash
./run.sh pull_sbas 20250607
```

### 2. Pull Observation Data

Pulls observation data for the requested site from PositioNZ (NZ sites) or AUS GA SFTP.  
Includes the last 15 minutes from the previous day and combines the data.

**Usage:**
```bash
./run.sh pull_obs <site> <date>
```
**Example:**
```bash
./run.sh pull_obs WGTN 250607
```

### 3. Pull Navigation Data

Pulls BRDC navigation data from CDDIS.  
Includes both the previous day and the target day, and combines them.

**Usage:**
```bash
./run.sh pull_nav <date>
```
**Example:**
```bash
./run.sh pull_nav 2025051
```

### 4. Copy Data to S3

Copies all pulled data for the specified date, compresses it, and uploads it to S3.

**Usage:**
```bash
./run.sh copy_to_s3 <date>
```
**Example:**
```bash
./run.sh copy_to_s3 051
```

---

### File Structure

```text
pull_data
├── copy_to_s3-doy.sh*
├── dockerfile
├── entrypoint.sh*
├── output/
│   └── [output files]
├── pull_nav-doy.sh*
├── pull_obs-station_doy.sh*
├── pull_sbas-doy.sh*
├── requirements.txt
├── run.sh
├── scripts/
│   └── [Scripts used by main scripts]
├── tools/
│   └── [Tools used by scripts]
```
