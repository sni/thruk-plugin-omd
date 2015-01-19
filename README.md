# OMD Thruk Plugin

This plugin saves top data every minute and renders nice graphs to drill down
performance problems on your monitoring host.

## Installation

All steps have to be done as site user

    %> cd etc/thruk/plugins-enabled/
    %> git clone https://github.com/sni/thruk-plugin-omd.git omd
    %> ln -sfn ~/etc/thruk/plugins-enabled/omd/cron ~/etc/cron.d/save_top_data
    %> omd reload crontab
    %> omd reload apache

You now have a new menu item under Reporting -> OMD Top.


## Screenshots

![Top Overview](ressources/top.png)


## License

This Addon is licensed under the GPLv3. See the LICENSE file for details.
