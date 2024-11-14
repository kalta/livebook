# Introduction

This directory contains a fork of Livebook, that can be run locally or can generate a docker container
that can be used in netkubes env

### Modifications:

* added lib/nk to add our code into Livebook
    * Nk.Cluster (will be started at Livebook.Application)
    * Nk.Node (will be started at Livebook.Application)
    * Nk.Util (called from Livebook.Application to create S3)
* .gitignore
* this file and scripts
* we are soft-linking config

### Scripts

* run.sh
* build.sh (only for testing)

### Build on Netkubes

* nkd build helm -r nk_lb_main -d rcp_livebook_dev
* nkd build helm -r nk_lb_base -d rcp_livebook_dev

This will build docker, send to AWS ECR and update deployment values




# Generation

* Forked https://github.com/livebook-dev/livebook into https://github.com/kalta/livebook
* git clone https://github.com/kalta/livebook nk_livebook
* git remote add upstream https://github.com/livebook-dev/livebook.git

Now we have two remotes, origin and upstream. Copy the tags from upstream:
* git fetch upstream --tags    
* checkout of upstream v0.14, created branch v0.14-nk, pushed to upstream 


# Runtimes

LIVEBOOK_DEFAULT_RUNTIME=standalone   # normal 
LIVEBOOK_DEFAULT_RUNTIME=embedded     # uses same engine from LB itself
LIVEBOOK_DEFAULT_RUNTIME=attached:rcp-infra-0@172.29.6.162:horasAtodasPIZZA

