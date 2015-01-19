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
