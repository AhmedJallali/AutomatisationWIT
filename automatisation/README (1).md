# Internal deployment script

The objective of the script ``deploy-webintake-kit.bash`` is to deploy Webintake on an Internal TestAutomation VM, using the Webintake installation kit.

**It should not be used by NeoXam clients. INTERNAL USE ONLY!!!**

## Main concepts
The main steps are:
* stopping Webintake
* deleting previous Webintake installation directories (``/home/testauto/nxia/webintake`` and ``/home/testauto/nxia/webintake-${version}``)
* downloading the kit from Artifactory
* installing Webintake (directory ``/home/testauto/nxia/webintake-${version}`` + symbolic link to ``/home/testauto/nxia/webintake``)

As a reminder, the kits are located here:
* **official kits**: https://access.my-nx.com/artifactory/webapp/#/artifacts/browse/tree/General/nxgp-webintake-generic-dev/installation-kit
* **testing kits**: https://access.my-nx.com/artifactory/webapp/#/artifacts/browse/tree/General/nxgp-webintake-generic-dev/for-test-use-only/installation-kit

## How to use
The script will use the file ``common.properties.orig.full`` embedded in the installation kit.

This file suggests values for some properties but not for all properties.

In consequence, it is needed to provide values for the ``##TO_CHANGE##`` properties.

It is also possible to override properties which already have a default value (like webintake_partitions, webintake_frontpage_env). It can be usefull to customize more precisely the environment.

To do that:
* manually create a properties file. This file should have the syntax of a **bash file** and variables should be set as **environment variables**:
````bash
#!/bin/bash
export prefix_ports=43
export server_name=$(hostname)
export webintake_frontpage_env="My Team Environment"
export webintake_partitions="client clyens1 middleware1"
...
````

* source this file afterwards to export all properties

````bash
. my-file
````

* launch the deployment script
````bash
./deploy-webintake-kit.bash ${WEBINTAKE_PATH} ${INSTALL_KEYCLOAK} ${DROP_INIT_WEBINTAKE_DATABASE}
./deploy-webintake-kit.bash webintake-5.2.2 Y N
````
where:
* **WEBINTAKE_PATH**: the Webintake installation path **relative** to the ``/home/testauto/nxia`` directory, ie: putting ``webintake-5.2.2`` will install Webintake in directory ``/home/testauto/nxia/webintake-5.2.2``
* **INSTALL_KEYCLOAK**: **Y** to install Keycloak, **N** otherwise
* **DROP_INIT_WEBINTAKE_DATABASE**: **Y** to drop Webintake and Keycloak databases, **N** otherwise. If Y is chosen, the empty databases schemas will be initialized using the Webintake init scripts

**In all cases, the Webintake Update Database script will be executed.**
