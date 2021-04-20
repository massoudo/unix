## **sapstart.sh**  
Start and stop SAP instances following a dependency order.  
Works on SAP NW and HANA DB. Useful for using with unix/linux *init.d*.  
  
Usage:    `sapstart.sh start|stop|status`  

### How to customize:
#### Set these parameters to suitable values for your installation:  
**`MAXWAITTIME`** (in seconds) Set max time to wait for instance to start/stop.  
**`INSTANCE_INDEXES`** Define an index ("**i**") for each instance. Format: space separated list.  
**`INSTANCE[<i>]`** List of instances. Format: `<host>,<System number>,<db name>,<os user>`  
**`INSTANCE_DEPENDENCY_<n>[<i>]`** List of dependencies. Format: `<host>,<System number>,<db name>`  
