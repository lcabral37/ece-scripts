# -*- mode: sh; sh-shell: bash; -*-

# ece-install module for installing the cache server

function install_varnish_software() {
  install_packages_if_missing varnish
  assert_commands_available varnishd
}

function install_cache_server() {
  print_and_log "Installing a caching server on $HOSTNAME ..."

  install_varnish_software

  backend_servers=(${fai_cache_backends})
  cache_port=${fai_cache_port-$default_cache_port}

  if [ -z "$backend_servers" ]; then
    backend_servers=("localhost:${appserver_port}")
  fi

  set_up_varnish $backend_servers
  leave_cache_trails

  add_next_step "Cache server is up and running at http://${HOSTNAME}:${cache_port}/"
}

function set_varnish_port() {
  log "Setting Varnish to listen on port" ${cache_port} "..."

  local file=/etc/default/varnish
  if [ $on_redhat_or_derivative -eq 1 ]; then
    file=/etc/sysconfig/varnish
  fi

  run sed -i -e "s/6081/${cache_port}/g" -e 's/^START=no$/START=yes/' $file
}

function create_varnish_conf_main() {
  # first, we define the main VCL file where all the others are included
  cat > ${varnish_conf_dir}/default.vcl <<EOF
/* Varnish configuration for Escenic Content Engine          -*- java -*-
 * generated by $(basename $0) @ $(date)
 *
 * The order of the VCL file inclusion is significant.
 */
include "host-specific.vcl";
include "backends.vcl";
include "access-control.vcl";
include "request-cleaning.vcl";
include "cache-key.vcl";
include "serve-stale-content.vcl";
include "compression.vcl";
include "robots-on-beta.vcl";
include "cookie-cleaner.vcl";
include "caching-policies.vcl";
include "varnish-hacks.vcl";
include "redirects.vcl";
include "cache-statistics.vcl";
include "error-pages.vcl";
EOF
}


function create_varnish_conf_host_specific() {
  local file=${varnish_conf_dir}/host-specific.vcl
  cat > $file <<EOF
sub vcl_deliver {
  set resp.http.X-Cache-Host = "${HOSTNAME}";
}
EOF
}

function create_varnish_conf_backends() {

  local file=${varnish_conf_dir}/backends.vcl
  echo > $file

  # first, define the ECE and EAE backends
  for (( i=0 ; i < ${#backend_servers[@]}; i++ )); do
    local old_ifs=$IFS
    IFS=':'
    read appserver_host appserver_port <<< "${backend_servers[$i]}"
    appserver_id=$(echo $appserver_host | sed 's/-/_/g')
    IFS=$old_ifs

    cat >> $file <<EOF
backend ${appserver_id}${i} {
  .host = "$appserver_host";
  .port = "$default_app_server_publication_port";
}

EOF
  done
print_and_log "Found anaysis engine host : $fai_analysis_host"
  if [ -n "${fai_analysis_host}" ]; then
    cat >> $file <<EOF
backend analysis {
  .host = "${fai_analysis_host}";
  .port = "${fai_analysis_port-${default_app_server_port}}";
  .max_connections = 50;
}

EOF
  fi

  # define a load balacner with session binding
  cat >> $file <<EOF
/* The client director gives us session stickiness based on client
 * IP. */
director webdirector client {
EOF

  for (( i=0 ; i < ${#backend_servers[@]}; i++ )); do
	  appserver_id=$(echo ${backend_servers[$i]} | cut -d':' -f1 | sed 's/-/_/g')
    cat >> $file <<EOF
  {
     .backend = ${appserver_id}${i};
     .weight = 1;
  }
EOF
  done

  # make use of the backends
  cat >> $file <<EOF
}
sub vcl_recv {
  /* This is the default backend */
  set req.backend = webdirector;

  if (req.url == "/.well-known/backend-health.txt") {
    error 200 "OK";
  }

EOF

  if [ -n "${fai_analysis_host}" ]; then
    cat >> $file <<EOF
  if (req.url ~ "^/analysis-logger/Logger" || req.url == "/analysis-logger/") {
    set req.backend = analysis;
    return(pass);
  }
EOF
  fi

  echo "}" >> $file
}

function create_varnish_conf_access_control() {
  local file=${varnish_conf_dir}/access-control.vcl
  cat > $file <<EOF
/* IPs that are allowed to access the administrative pages/webapps. */
acl staff {
  "localhost";
}

sub vcl_recv {
  if (!client.ip ~ staff &&
      (req.url ~ "^/escenic/" ||
       req.url ~ "^/studio/" ||
       req.url ~ "^/munin/" ||
       req.url ~ "^/icinga/" ||
       req.url ~ "^/webservice/" ||
       req.url ~ "^/webservice-extensions/" ||
       req.url ~ "^/escenic-admin/")) {
    error 405 "Not allowed.";
  }
}
EOF
}

function create_varnish_conf_request_cleaning() {
  local file=${varnish_conf_dir}/request-cleaning.vcl
  cat > $file <<EOF
sub vcl_recv {
  /* Normalizing all user agents so that we can support both caching
   * and (partial) device detection on backend servers like
   * VMEO/Adactus and Mobiletech .
   *
   * All iPhones are treated as the same one, all iPads as the same
   * iPad, all Opera Mini as the same one and all Android. If the
   * client (browser) is neither of the above, a common UA string is
   * set.
   *
   * We check for Opera Mini before Android as some user agents
   * contain both.
   */
  if (req.http.User-Agent ~ "iPhone") {
    set req.http.User-Agent = "Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en_us) AppleWebKit/525.18.1 (KHTML, like Gecko)";
  }
  else if (req.http.User-Agent ~ "iPad") {
    set req.http.User-Agent = "Mozilla/5.0 (iPad; U; CPU OS 4_3_2 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8H7 Safari/6533.18.5";
  }
  else if (req.http.User-Agent ~ "Opera Mini" ||
           req.http.User-Agent ~ "Opera Mobi") {
    set req.http.User-Agent = "Opera/9.80 (J2ME/MIDP; Opera Mini/4.0.10031/28.3392; U; en) Presto/2.8.119 Version/11.10";
    set req.http.X-OperaMini-Phone-UA = "NokiaX2-00/5.0 (08.35) Profile/MIDP-2.1 Configuration/CLDC-1.1 Mozilla/5.0 AppleWebKit/420+ (KHTML, like Gecko) Safari/420+";
  }
  else if (req.http.User-Agent ~ "Android") {
    // we don't do anything for Android devices right now since there
    // are just too many different ones.
    //
    // We could cache two versions, one mobile, one table for each
    // Android 2.0-2.4, however, we try to leave it be right now and
    // see how big the cache gets.
  }
  else {
    set req.http.User-Agent = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; VOSA 1.0)";
  }
}

/* We remove all request headers before hitting the backend, except:
 * - Host
 * - User-Agent
 * - X-Forwarded-For
 * - Referer
 * - Accept
 * - X-OperaMini-Phone-UA
 *
 * The reason for this, is that we're optimising the device detection
 * through the use of buckets. Hence, we must remove all headers that
 * backend software (such as Mobiletech) may use to determine the
 * client and by that deliver web content. */
sub vcl_miss {
  remove bereq.http.accept-charset;
  remove bereq.http.accept-encoding;
  remove bereq.http.accept-language;
  remove bereq.http.accept-ranges;
  remove bereq.http.accounting-session-id;
  remove bereq.http.apn;
  remove bereq.http.authorization;
  remove bereq.http.bearer-type;
  remove bereq.http.cache-control;
  remove bereq.http.charging-characteristics;
  remove bereq.http.clientip;
  remove bereq.http.client-ip;
  remove bereq.http.connection;
  remove bereq.http.content-disposition;
  remove bereq.http.content-length;
  remove bereq.http.content-range;
  remove bereq.http.content-type;
  remove bereq.http.cookie;
  remove bereq.http.cookie2;
  remove bereq.http.cuda_cliip;
  remove bereq.http.date;
  remove bereq.http.device-stock-ua;
  remove bereq.http.dnt;
  remove bereq.http.drm-version;
  remove bereq.http.etag;
  remove bereq.http.expires;
  remove bereq.http.from;
  remove bereq.http.if-modified-since;
  remove bereq.http.if-none-match;
  remove bereq.http.if-range;
  remove bereq.http.ip-address;
  remove bereq.http.last-modified;
  remove bereq.http.location;
  remove bereq.http.msisdn;
  remove bereq.http.mt-proxy-id;
  remove bereq.http.nas-ip-address;
  remove bereq.http.origin;
  remove bereq.http.pnp;
  remove bereq.http.pragma;
  remove bereq.http.proxy-connection;
  remove bereq.http.range;
  remove bereq.http.server;
  remove bereq.http.set-cookie;
  remove bereq.http.sgsn-ip-address;
  remove bereq.http.transfer-encoding;
  remove bereq.http.ua-cpu;
  remove bereq.http.unless-modified-since;
  remove bereq.http.vary;
  remove bereq.http.via;
  remove bereq.http.wap-connection;
  remove bereq.http.x-amz-cf-id;
  remove bereq.http.x-att-deviceid;
  remove bereq.http.x-bluecoat-via;
  remove bereq.http.x-cnection;
  remove bereq.http.x-country-code;
  remove bereq.http.x-d-forwarder;
  remove bereq.http.x-ebo-ua;
  remove bereq.http.x-ee-brand-id;
  remove bereq.http.x-ee-client-ip;
  remove bereq.http.x-flash-version;
  remove bereq.http.x-forwarded-port;
  remove bereq.http.x-forwarded-proto;
  remove bereq.http.x-imforwards;
  remove bereq.http.x-mcproxyfilter;
  remove bereq.http.x-mobile-gateway;
  remove bereq.http.x-network-type;
  remove bereq.http.x-nokia-bearer;
  remove bereq.http.x-nokiabrowser-features;
  remove bereq.http.x-nokia-device-type;
  remove bereq.http.x-nokia-ipaddress;
  remove bereq.http.x-nokia-musicshop-bearer;
  remove bereq.http.x-nokia-musicshop-version;
  remove bereq.http.x-nokia-upgradeid;
  remove bereq.http.x-ob;
  remove bereq.http.x-online-host;
  remove bereq.http.x-opera-id;
  remove bereq.http.x-opera-info;
  remove bereq.http.x-operamini-features;
  remove bereq.http.x-operamini-phone;
  remove bereq.http.x-operamini-route;
  remove bereq.http.x-operator-domain;
  remove bereq.http.x-orange-rat;
  remove bereq.http.x-orange-roaming;
  remove bereq.http.x-p2p-peerdist;
  remove bereq.http.x-p2p-peerdistex;
  remove bereq.http.x-piper-id;
  remove bereq.http.x-powered-by;
  remove bereq.http.x-proxy-id;
  remove bereq.http.x-proxyuser-ip;
  remove bereq.http.x-purpose;
  remove bereq.http.x-rbt-optimized-by;
  remove bereq.http.x-requested-with;
  remove bereq.http.x-ucbrowser-phone;
  remove bereq.http.x-ucbrowser-phone-ua;
  remove bereq.http.x-ucbrowser-ua;
  remove bereq.http.x-up-calling-line-id;
  remove bereq.http.x-up_devcap-screendepth;
  remove bereq.http.x-view-mode;
  remove bereq.http.x-wap-network-client-msisdn;
  remove bereq.http.x-wap-profile;
  remove bereq.http.x-wap-profile-diff;
}
EOF
}

function create_varnish_conf_cache_key() {
  local file=${varnish_conf_dir}/cache-key.vcl
  cat > $file <<EOF
/* Manipulate the cache keys in this method. */
sub vcl_hash {
  /* We've normalised the UA string in request-cleaning.vcl so we can
   * include the UA in the hash */
  hash_data(req.http.User-Agent);
}
EOF
}

function create_varnish_conf_serve_stale_content() {
  local file=${varnish_conf_dir}/serve-stale-content.vcl
  cat > $file <<EOF
backend unhealthy {
  .host = "127.0.0.1";
  .port = "1";
  .probe = {
    .url = "/fake.html";
    .interval = 600s;
    .timeout = 0.1s;
    .window = 1;
    .threshold = 1;
    .initial = 1;
  }
}

sub vcl_recv {
  /* We accept up to this old data, if backends for some reason
   * don't deliver (fresh) content, typically when they're down */
  set req.grace = 2h;

  if (req.http.unhealthy && req.http.unhealthy == "true" ) {
    set req.backend = unhealthy;
  }
}

sub vcl_fetch {
  /* Store objects 1 hour after they are due to be purged for
   * grace-purposes (this means that we've got 1 hour to serve stale
   * content in case of failing backends).
  */
  if (beresp.status == 200) {
    set beresp.grace = 1h;
  }
  else if (beresp.status == 503) {
    /* For this URL, don't ask the backend again for this amount of
     * time. */
    set beresp.saintmode = 60s;
    return(restart);
  }
}

sub vcl_error {
  /* If we're serving a 503 and haven't restarted (this means the
   * backend is down, 503 is the typical Varnish 'guru meditation',
   * try to invoke grace mode. We do this by setting the backend to be
   * the unhealthy, phony packend. This will never work, so Varnish
   * will invoke grace mode, i.e. serve stale/old content from the
   * previous status=200 for that URL.  */
  if (obj.status == 503 && req.restarts == 0) {
    set req.http.unhealthy = "true";
    return(restart);
  }
}
EOF
}

function create_varnish_conf_compression() {
  local file=${varnish_conf_dir}/compression.vcl
  cat > $file <<EOF
sub vcl_fetch {
  if (beresp.http.content-type ~ "^text/" || 
      beresp.http.content-type == "application/javascript") {
    set beresp.do_gzip = true;
  }
}
EOF
}

function create_varnish_conf_robots_on_beta() {
  local file=${varnish_conf_dir}/robots-on-beta.vcl
  cat > $file <<EOF
sub vcl_recv {
  if (req.http.host ~ "^beta\." && req.url == "/robots.txt") {
    set req.http.marker-robots = "true";
    error 200 "OK";
  }
}

sub vcl_error {
  if (obj.status == 200 && req.http.marker-robots == "true") {
    remove req.http.marker-robots;
    synthetic {"User-Agent: *
Disallow /
"};
    return(deliver);
  }
}
EOF
}

function create_varnish_conf_cookie_cleaner() {
  local file=${varnish_conf_dir}/cookie-cleaner.vcl
  cat > $file <<EOF
sub vcl_recv {
  /* remove all cookies, except the poll cookie see
   * https://www.varnish-cache.org/trac/wiki/VCLExampleRemovingSomeCookies#RemovingallBUTsomecookies */
  if (req.http.Cookie) {
    set req.http.Cookie = ";" + req.http.Cookie;
    set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
    set req.http.Cookie = regsuball(req.http.Cookie, ";(mentometer)=", "; \1=");
    set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

    if (req.http.Cookie == "") {
      remove req.http.Cookie;
    }
  }
}

sub vcl_fetch {
  if (beresp.status == 200) {
    remove beresp.http.Set-Cookie;
  }
}
EOF
}

function create_varnish_conf_caching_policies() {
  local file=${varnish_conf_dir}/caching-policies.vcl
  cat > $file <<EOF
sub vcl_fetch {
  /*   Cache everything for 2 minutes. */
  if (beresp.status == 200) {
    set beresp.ttl = 2m;
  }

  /* Remove cookies from these resource types and cache them for a
   * long time */
  if (req.url ~ "\.(png|gif|jpg|css|js)$" || beresp.http.content-type ~ "^image/" ||
      req.url == "/favicon.ico" && beresp.status == 200) {
    set beresp.ttl = 5h;
  }
}

sub vcl_deliver {
  if (resp.http.content-type ~ "^image/" && resp.status == 200) {
    set resp.http.Cache-Control = "public, max-age=3600";
  }
  else if ((req.url ~ "\.(css|js)$" || req.url == "/favicon.ico") &&
           resp.status == 200) {
    set resp.http.Cache-Control = "public, max-age=7200";
  }

  /* Since we're normalising the UA, we include it in the Vary header
   * so that itermiediary proxies get all the information they need to
   * create desired behaviour. We also add a debug header to show
   * which UA we've used to produce the response. */
  set resp.http.X-UA = req.http.User-Agent;
  set resp.http.Vary = "Accept-Encoding,User-Agent";
}
EOF

  # if you've normalised the UA, add
  # resp.http.Vary = "Accept-Encoding,User-Agent";
  # at the end of the vcl_deliver above.
}

function create_varnish_conf_hacks() {
  local file=${varnish_conf_dir}/varnish-hacks.vcl
  cat > $file <<EOF
sub vcl_deliver {
  /* It seems that Varnish changes the Date header and the age header
   * becomes wrong because of this. For this reason, we set the Age
   * header to 0 to be standards compliant. */
  set resp.http.Age = "0";
}
EOF
}

function get_from_domain() {
  if [[ $1 == "^www." ]]; then
    echo $1 | sed 's/^www.//g'
  else
    echo "www.${1}"
  fi
}

function create_varnish_conf_redirects() {
  local file=${varnish_conf_dir}/redirects.vcl
  echo "" > $file

  if [ -n "${fai_publication_domain_mapping_list}" ]; then
    echo "sub vcl_recv {" > $file

    for el in $fai_publication_domain_mapping_list; do
      local old_ifs=$IFS
      IFS='#'
      read publication publication_domain publication_aliases <<< "$el"
      IFS=$old_ifs

      local from_domain=$(get_from_domain $publication_domain)

      cat >> $file <<EOF
  if (req.http.host == "${from_domain}") {
    error 301 "Moved Temporarily";
  }
EOF
    done

    cat >> $file <<EOF
}

sub vcl_error {
  /* We want both web sites to be identified by one URL, hence we make
   * an HTTP re-direct here. See vcl_recv for how these 301 error
   * directives.
   */
EOF
    for el in $fai_publication_domain_mapping_list; do
      local old_ifs=$IFS
      IFS='#'
      read publication publication_domain publication_aliases <<< "$el"
      IFS=$old_ifs

      local from_domain=$(get_from_domain $publication_domain)

      cat >> $file <<EOF
  if (obj.status == 301 && req.http.host == "${from_domain}") {
    set obj.http.Location = "http://${publication_domain}" + req.url;
    return (deliver);
  }
EOF
    done

    echo "}" >> $file
  fi
}

function create_varnish_conf_cache_statistics() {
  local file=${varnish_conf_dir}/cache-statistics.vcl
  cat > $file <<EOF
sub vcl_deliver {
  /* Adds debug header to the result so that we can easily see if a
   * URL has been fetched from cache or not.
   */
  if (obj.hits > 0 && (resp.status == 200 || resp.status == 301)) {
    set resp.http.X-Cache = "HIT #" + obj.hits + "/" + resp.http.Age + "s";
  }
  else if (resp.status == 200) {
    set resp.http.X-Cache = "MISS";
  }
  set resp.http.X-Cache-Backend = req.backend;
}
EOF
}

function create_varnish_conf_error_pages() {
  local file=${varnish_conf_dir}/error-pages.vcl
  echo "" > $file
}

function create_varnish_conf() {
  varnish_conf_dir=${fai_cache_conf_dir-/etc/varnish}

  create_varnish_conf_main
  create_varnish_conf_host_specific
  create_varnish_conf_backends
  create_varnish_conf_access_control
  create_varnish_conf_request_cleaning
  create_varnish_conf_cache_key
  create_varnish_conf_serve_stale_content
  create_varnish_conf_compression
  create_varnish_conf_robots_on_beta
  create_varnish_conf_cookie_cleaner
  create_varnish_conf_caching_policies
  create_varnish_conf_hacks
  create_varnish_conf_redirects
  create_varnish_conf_cache_statistics
  create_varnish_conf_error_pages
}

function set_up_varnish() {
  print_and_log "Setting up Varnish to match your environment ..."
  run /etc/init.d/varnish stop
  set_varnish_port
  create_varnish_conf
  run /etc/init.d/varnish start
}

function leave_cache_trails() {
  leave_trail "trail_cache_host=${HOSTNAME}"
  leave_trail "trail_cache_port=${cache_port}"
  leave_trail "trail_cache_backend_servers=$backend_servers"
}
