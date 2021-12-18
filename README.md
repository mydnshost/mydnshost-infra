# mydnshost-infra

This repo is the base repo to run the mydnshost web infrastructure on a single server. This will allow you to deploy and upgrade all the required containers to have a functioning deployment.

Public-Facing nameservers are deployed using [mydnshost-bind](https://github.com/mydnshost/mydnshost-bind)

## Installation

Firstly, you need a fresh Ubuntu 20.04 Install, fully up to date.

Perform all the following steps as root.

### Disable systemd-resolved
systemctl disable systemd-resolved.service
systemctl stop systemd-resolved

### Install deps

```bash
apt-get install git
```

### Install Docker

This is based on https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-docker-ce

```bash
apt-get install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io
```

### Install docker-compose

Based on https://docs.docker.com/compose/install/#install-compose

```bash
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
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

Of note:
**bind_rndc.conf**
- You will want to update the key used here (and remember it for docker-compose.override.yml and rndc_rndc.conf)

**docker-compose.override.yml**
- You will want to replace `somehost` with your instance domain name (eg `mydnshost.co.uk`)
- `gmworker1` will need SMTP server details given to allow emails to be sent.
- You will want to ensure the database root password is set.
- The `STATUSCAKE_` and env vars for the `maintenance` container are used for monitoring, 3rd party deployments can probably leave this alone, so just leave them blank. `INFLUX_BIND_SLAVES` is used by the `gather-statistics` cron to pull data from the public-facing servers, format is something like: `INFLUX_BIND_SLAVES=ns1=10.0.0.1, ns2=10.0.0.2, ns3=10.0.0.3`. Leave blank to disable this.
- `bind` container needs it's own public IP eg `MASTER=1.1.1.1;` and then the IPs of the public-facing servers as `SLAVES=10.0.0.1; 10.0.0.2; 10.0.0.3;`), You will want to ensure you copy the bind rndc key from bind_rndc.conf also.
- `chronograf` requires oauth configuration to run otherwise it will refuse to start. See: https://docs.influxdata.com/chronograf/v1.9/administration/managing-security/#configure-github-authentication
- There are other things you can override based on the `docker.compose.yml` but the things in this file already are the minimum to get things functional.

**rndc_rndc.conf**
- You will want to update the key used here to the same one used elsewhere

**api-config.local.php**
- The default records here probably need changing, also the slave servers.
- Other settings (as per `config.php` in mydnshost/api-base) can be set here also, or overridden with ENV vars in some cases.

**frontent-config.local.php**
- Nothing needs to go in here unless you wish to override settings from (as per `config.php` in mydnshost/frontend) in a way that can't be done with ENV vars.

**traefik/traefik.toml**
- Nothing should need changing here.

**logstash/logstash.conf**
- Nothing should need changing here.

### Bring services up / Update running services.

Running the following script will bring up all the required containers, and upgrade them as required.

```bash
./update.sh
```

Occasionally you will need to clean up old docker files after a few upgrades to keep disk usage sane:

```bash
./cleanup.sh
```

You can now run `docker-compose exec api /dnsapi/admin/createAdmin.php` to create your first admin user.

`docker-compose exec` only works for the first run of the api container, if your api container has updated before you created the admin user or you want to create more from the command line, you can use this instead to run the command in the latest instance of the api container:

`docker exec -it $(docker-compose ps api | tail -n 1 | awk '{print $1}') /dnsapi/admin/createAdmin.php`

### Setting up public slave servers

On fresh ubuntu 20.04 installs, run through the steps up to "Install docker-compose" from above.

Run the following commands:

```bash
export MASTER="1.1.1.1;"
export SLAVES="10.0.0.1; 10.0.0.2; 10.0.0.3;"
export RNDCKEY="REPLACEME"
export STATISTICS="1.1.1.1; 10.0.0.1; 10.0.0.2; 10.0.0.3;"

cd /root
git clone https://github.com/shanemcc/mydnshost-bind
cd mydnshost-bind

./deploy_local_slave.sh

docker-compose up -d
```

Replace the contents of the ENV vars with the same values used for the `bind` container in `docker-compose.override.yml`. The `STATISTICS` var is which hosts are allowed query for statistics, this should at the very least include the IP of the server running the `maintenance` container.
