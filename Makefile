# dcape-app-drone Makefile

SHELL               = /bin/bash
CFG                ?= .env

# Database name and database user name
DB_USER            ?= drone
# Database user password
DB_PASS            ?= $(shell < /dev/urandom tr -dc A-Za-z0-9 | head -c14; echo)

# Site host
APP_SITE           ?= drone.dev.lan

# Password for drone-server <-> drone-agent exchange
DRONE_SECRET       ?= $(shell < /dev/urandom tr -dc A-Za-z0-9 | head -c14; echo)
# Gitea user who will be Drone admin
DRONE_ADMIN        ?= admin
# Gitea url hostname
DRONE_GIT_HOST     ?= git.dev.lan
# Gitea url proto
DRONE_GIT_PROTO    ?= http

# Docker image name
IMAGE              ?= drone/drone
# Docker image tag
IMAGE_VER         ?= 0.7
# Docker-compose project name (container name prefix)
PROJECT_NAME       ?= drone
# dcape container name prefix
DCAPE_PROJECT_NAME ?= dcape
# dcape network attach to
DCAPE_NET          ?= $(DCAPE_PROJECT_NAME)_default
# dcape postgresql container name
DCAPE_DB           ?= $(DCAPE_PROJECT_NAME)_db_1

define CONFIG_DEF
# ------------------------------------------------------------------------------
# Drone settings

# Site host
APP_SITE=$(APP_SITE)

# Password for drone-server <-> drone-agent exchange
DRONE_SECRET=$(DRONE_SECRET)
# Gitea user who will be drone admin
DRONE_ADMIN=$(DRONE_ADMIN)
# Gitea url hostname
DRONE_GIT_HOST=$(DRONE_GIT_HOST)
# Gitea url proto
DRONE_GIT_PROTO=$(DRONE_GIT_PROTO)

# Database name and database user name
DB_USER=$(DB_USER)
# Database user password
DB_PASS=$(DB_PASS)

# Docker details

# Docker image name
IMAGE=$(IMAGE)
# Docker image tag
IMAGE_VER=$(IMAGE_VER)
# Docker-compose project name (container name prefix)
PROJECT_NAME=$(PROJECT_NAME)
# dcape network attach to
DCAPE_NET=$(DCAPE_NET)
# dcape postgresql container name
DCAPE_DB=$(DCAPE_DB)

endef
export CONFIG_DEF

-include $(CFG)
export

.PHONY: all $(CFG) setup start stop up reup down docker-wait db-create db-drop psql dc help

all: help

# ------------------------------------------------------------------------------
# webhook commands

start: db-create up

start-hook: db-create reup

stop: down

update: reup

# ------------------------------------------------------------------------------
# docker commands

## старт контейнеров
up:
up: CMD=up -d
up: dc

## рестарт контейнеров
reup:
reup: CMD=up --force-recreate -d
reup: dc

## остановка и удаление всех контейнеров
down:
down: CMD=rm -f -s
down: dc


# Wait for postgresql container start
docker-wait:
	@echo -n "Checking PG is ready..."
	@until [[ `docker inspect -f "{{.State.Health.Status}}" $$DCAPE_DB` == healthy ]] ; do sleep 1 ; echo -n "." ; done
	@echo "Ok"

# ------------------------------------------------------------------------------
# DB operations

# create user, db and load sql
db-create: docker-wait
	@echo "*** $@ ***" ; \
	docker exec -i $$DCAPE_DB psql -U postgres -c "CREATE USER \"$$DB_USER\" WITH PASSWORD '$$DB_PASS';" || true ; \
	docker exec -i $$DCAPE_DB psql -U postgres -c "CREATE DATABASE \"$$DB_USER\" OWNER \"$$DB_USER\";" || db_exists=1 ; \
	docker exec -i $$DCAPE_DB psql -U postgres -d $$DB_USER -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" || true ; \

## drop database and user
db-drop: docker-wait
	@echo "*** $@ ***"
	@docker exec -it $$DCAPE_DB psql -U postgres -c "DROP DATABASE \"$$DB_USER\";" || true
	@docker exec -it $$DCAPE_DB psql -U postgres -c "DROP USER \"$$DB_USER\";" || true

psql: docker-wait
	@docker exec -it $$DCAPE_DB psql -U $$DB_USER

# ------------------------------------------------------------------------------

# $$PWD используется для того, чтобы текущий каталог был доступен в контейнере по тому же пути
# и относительные тома новых контейнеров могли его использовать
## run docker-compose
dc: docker-compose.yml
	@docker run --rm  \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v $$PWD:$$PWD \
	  -w $$PWD \
	  docker/compose:1.14.0 \
	  -p $$PROJECT_NAME \
	  $(CMD)

# ------------------------------------------------------------------------------

$(CFG):
	@echo "$$CONFIG_DEF" > $@

# ------------------------------------------------------------------------------

## List Makefile targets
help:
	@grep -A 1 "^##" Makefile | less

##
## Press 'q' for exit
##
