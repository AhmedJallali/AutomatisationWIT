#!/bin/bash
#export NXIA_DIR=/home/testauto/nxia/webintake
export prefix_ports=44
export server_name=degroof-nxdh-aja
export webintake_host=GP4-WIT-HOST
export webintake_su_user=testauto
export context_url=gp4
export webintake_frontpage_env=AutoEnvironment
export webintake_partitions="client clyens1 clypy1 middleware1 middleware2 middleware3 reporting"
export runtime_host=GP4-RT-HOST
export runtime_prefix_ports=44
export db_type=oracle
export oracle_home=/oracle/product/19.3.0
export webintake_db_host=GP4-DB-HOST
export webintake_db_port=1521
export webintake_db_user=WEBINTAKE
export webintake_db_password=WEBINTAKE
export webintake_db_oracle_service_name=GPCORE
#In case of upgrading from 5.1.X to 5.2.X ONLY
export runtime_db_host=GP4-DB-HOST
export runtime_db_port=1521
export runtime_db_user=CORE
export runtime_db_password=CORE
export runtime_db_oracle_service_name=GPCORE