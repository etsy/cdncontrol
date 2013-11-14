CDNControl
===========
CDNControl is a rubygem which provides an interface to Dyn's GSLB service. It's used by Etsy to control the balance of traffic between our CDN providers, and also to enable or disable individual CDNs.

Installation
------------

### Gem Install
`cdncontrol` is available on rubygems. Add the following to your `Gemfile`:

```ruby
gem 'cdncontrol'
```

or install the gem manually:

```bash
gem install cdncontrol
```

The gem installs the *cdncontrol* binary at ```/usr/bin/cdncontrol```
CDNControl Configuration
-------------------
CDNControl requires a configuration file in order to function, which needs to be in ```/usr/local/etc/cdncontrol.conf```


Below is a sample config file with all supported options included, followed by an explanation of each section.

```yaml
organization: "myorganisation"
username: "username"
password: "password"
output_path: "/var/www"
cdncontrol_ui_hostname: "http://cdn.mydomain.com"


valid_providers:
    - provider1
    - provider2
    - provider3

targets:
    target1:
        zone: myzone.com
        nodes:
          - 1.myzone.com
          - 2.myzone.com
          - 3.myzone.com
          - 4.myzone.com
        graph_url: "<your_graphite_cdn_metric_url>"
        graph_color_key:
           provider1: "#FF7400"
           provider2: "#1240AB"
           provider3: "#00CC00"
           provider4: "#380470"

```

#### Organization
The `organization` directive specifies the customer name you use when logging into the DynECT portal

####Username
The `username` directive specifies the username to use when authenticating to the Dyn API.

####Password
The `password` directive specifies the password to use when authenticating to the Dyn API.

####Output Path
The `output_path` directive specifies where cdncontrol should dump JSON containing the CDN balances.

####CDNControl UI Hostname (Optional)
The `cdncontrol_ui_hostname` directive specifies the hostname where the CDNControlUI web application can be reached, if you're using it.

####Valid Providers
The `valid_providers` section specifies the valid CDN providers which may be configured with this tool. This corresponds to the names of the global pools you have configured on the Dyn GSLB platform.

####Targets
The `targets` section of the config file lists the different site configurations you want to use cdncontrol to manage. The following are the parameters which can be used to configure a target (in this case, we're looking at the parameters of *target1* above:

* **zone**: This is the name used to configure the site in Dyn's GSLB platform. In the DynECT web interface, this is the top-level site from which all of your nodes are configured
* **nodes**: These are the nodes under the zone which are configured to use GSLB. For example, if your zone is *mydomain.com*, you might configure GSLB for *img0.mydomain.com* and *img1.mydomain.com*. These should all be specified here.
* **graph_url** (optional): If you're using the CDNControlUI web interface to this tool, this option lets you specify a graph_url to be displayed on the page for this target.
* **graph_color_key** (optional): If you're using the CDNControlUI web interface to this tool, this option lets you specify a color key to be displayed above the graph (to indicate which CDN is which color, for example).



CDNControl Usage
================

### Supported Options
```
$> cdncontrol
Usage: cdncontrol [-tpwmcsav]
Please specify the command in one of the following formats:

cdncontrol -t TARGET --show
cdncontrol -t TARGET --write
cdncontrol -t TARGET -p PROVIDER -w WEIGHT
cdncontrol -t TARGET -p PROVIDER -m MODE
cdncontrol -t TARGET -a -p PROVIDER -c CNAME

Specific options:
    -t, --target                     The configuration to work on (one of <targets specified in your config file>)
    -p, --provider                   Provider to modify (one of <providers specified in your config file>)
    -w, --weight                     Weight of traffic to send to provider (value between 1 and 15)
    -m, --mode                       Set the serve mode of the provider (one of always,obey,remove,no)
    -c, --cname                      Target CNAME for new provider
    -s, --show                       Show current provider ratios
    -v, --verbose                    Show me in excrutiating detail what is happening
        --write                      Dump all weights out to JSON files
```

### Viewing target details
```
$> cdncontrol -t test --show

** connecting to dynect API
** fetching node details .......done!

NODE BALANCE
============
img0.mydomain.com
  provider1       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider1.com.
  provider2       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider2.com.
  provider3       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider3.com.
```

### Writing target details as JSON
```
$ cdncontrol -t test --write
** connecting to dynect API
** fetching node details .......done!
** Updated details in /var/www/cdn_test.json
```

### Setting the weight of a target's provider
```
$> cdncontrol -t test -p provider1 -w 5
** connecting to dynect API
** fetching node details .......done!

CURRENT LIVE WEIGHTS
====================
img0.mydomain.com
  provider1       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider1.com.
  provider2       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider2.com.
  provider3       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider3.com.

You're about to modify the weight of provider1 to 5 are you sure (Y|N)? Y

** setting weight = 5 on GSLBRegionPoolEntry/myorg-mydomain.com/img0.mydomain.com/global/cdn.provider1.com.

** fetching node details .......done!

NODE WEIGHTS AFTER CHANGE
=========================
img0.mydomain.com
  provider1       weight = 5 | serve_mode = always   | status = up   | address = cdn.provider1.com.
  provider2       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider2.com.
  provider3       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider3.com.

** Updated details in /var/www/cdn_test.json
```

### Setting the mode of a target's provider
```
 cdncontrol -t test -p provider1 -m no
** connecting to dynect API
** fetching node details .......done!

CURRENT SERVE MODES AND WEIGHTS
===============================
img0.mydomain.com
  provider1       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider1.com.
  provider2       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider2.com.
  provider3       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider3.com.

You're about to change the serving mode for provider1 to 'no' are you sure (Y|N)? Y

** setting serve_mode = no on GSLBRegionPoolEntry/myorg-mydomain.com/img0.mydomain.com/global/cdn.provider1.com.
** fetching node details .......done!

NODE SERVE MODES AFTER CHANGE
=============================
img0.mydomain.com
  provider1       weight = 15 | serve_mode = no       | status = up   | address = cdn.provider1.com.
  provider2       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider2.com.
  provider3       weight = 15 | serve_mode = always   | status = up   | address = cdn.provider3.com.

** Updated details in /var/www/cdn_test.json
```
