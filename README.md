# mydnshost-infra

This repo is the base repo to run the mydnshost web infrastructure on a single server. This will allow you to deploy and upgrade all the required containers to have a functioning deployment.

Public-Facing nameservers are deployed using [mydnshost-bind](https://github.com/mydnshost/mydnshost-bind)

## Installation

Firstly, you need a fresh Ubuntu 16.04 Install, fully up to date.

Perform all the following steps as root.

### Install deps

```bash
apt-get install git
```

### Install Docker

This is based on https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-docker-ce

```bash
apt-get install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
apt-key fingerprint 0EBFCD88
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install docker-ce
```

### Install docker-compose

Based on https://docs.docker.com/compose/install/#install-compose

```bash
curl -L https://github.com/docker/compose/releases/download/1.15.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod a+x /usr/local/bin/docker-compose
```
### Clone repository

Clone the main infra repo

```bash
cd /root
git clone https://github.com/mydnshost/mydnshost-infra.git mydnshost
```
### Copy example files to non-example files

The main repo contains a bunch of .example files that need to be copied to non-example files for production use. This is to prevent repo updates from overwriting local changes.

```bash
cp bind_rndc.example.conf bind_rndc.conf
cp docker-compose.override.example.yml docker-compose.override.yml
cp rndc_rndc.example.conf rndc_rndc.conf
cp api-config.local.example.php api-config.local.php
cp frontend-config.local.example.php frontend-config.local.php
cp traefik/traefik.example.toml traefik/traefik.toml
cp logstash/logstash.example.conf logstash/logstash.conf
```
### Edit non-example files as needed.

You will need to edit all of the non-example files to suit your deployment.

```bash
nano bind_rndc.conf docker-compose.override.yml rndc_rndc.conf api-config.local.php frontend-config.local.php traefik/traefik.toml logstash/logstash.conf
```

### Bring services up / Update running services.

Running the following script will bring up all the required containers, and upgrade them as required.

```bash
./update.sh
```

Occasionally you will need to cleanup old docker files after a few upgrades to keep disk usage sane:

```bash
./cleanup.sh
```
