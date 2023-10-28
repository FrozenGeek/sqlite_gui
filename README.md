### What is OpenRVDAS
Read up on the parent project [here](https://github.com/OceanDataTools/openrvdas)

### OpenRVDAS Sqlite GUI
OK... if you've arrived here, you're out on the bleeding edge.

This is an early pass at a Django-free, pure-SQLite+Javascript GUI for OpenRVDAS. To use it,
check this repository out in a separate directory, e.g.

    /opt/oceandatatools/sqlite_gui

Then create a symlink to it from the OpenRVDAS root directory.

    cd /opt/openrvdas
    ln -s /opt/oceandatatools/sqlite_gui

Then run the SQLite GUI installation script.

    cd sqlite_gui
    utils/install_sqlite_gui.sh

Once that has completed, you'll need to create a user for the SQLite web interface:

    cgi-bin/user_tool.py -add --user <user> --password <password>

The configuration file ``sqlite_gui/js/openrvdas.js`` contains installation-specific
file paths that you may need to customize to allow the GUI access to any cruise
configurations that you want to load. The variables ``confdir`` and ``safedir`` near
the bottom of the file specify which directories will be accessible for loading configurations.

Prior to starting the SQLite GUI interface, you will need to shut down the existing
Django-based GUI using supervisorctl:

    supervisorctl stop openrvdas:logger_manager web:*
    supervisorctl start sqlite:*

Assuming the scripts all start up without complaint, at this point going to
https://hostname should take you to the initial (still
rudimentary) SQLite GUI page.
