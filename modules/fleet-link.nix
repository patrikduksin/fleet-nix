# One MCP for the whole fleet. The hub links every machine on the tailnet that
# carries `fleet.tag`, so an agent signed in to the hub's /mcp (the Grok
# connector, over the tailnet) can start, message and stop threads on any of them.
#
# Membership is the tag: `tailscale up --advertise-tags=tag:t3-fleet` on a
# machine, nothing to change on the hub. Every 6 hours, and 3 minutes after
# boot, t3-fleet-link on the hub:
# - links each online tagged machine it has no fresh link to: it mints a
#   5-minute pairing code there over SSH (the hub's key is in fleet.sshKeys)
#   and runs `t3 environment link` with `fleet.access`;
# - renews a link a week before its 30 days run out;
# - unlinks machines that lost the tag or left the tailnet. Offline machines
#   keep their link.
{ config, lib, pkgs, ... }:
let
  cfg = config.fleet;
  port = toString cfg.servePort;
  t3 = "${pkgs.t3code}/bin/t3";

  linkFleet = pkgs.writeShellScript "t3-fleet-link" ''
    set -uo pipefail
    status=$(tailscale status --json) || { echo "tailscale is not answering"; exit 1; }
    links=$(${t3} environment list --json) || { echo "T3 Code is not answering"; exit 1; }
    suffix=$(jq -r '.MagicDNSSuffix' <<<"$status")
    renew_before=$(( $(date +%s) + 7 * 86400 ))
    failed=0

    # Tagged peers, as "<online> <dns name>".
    members=$(jq -r --arg tag ${lib.escapeShellArg cfg.tag} \
      '.Peer // {} | .[] | select((.Tags // []) | index($tag)) | "\(.Online) \(.DNSName | rtrimstr("."))"' <<<"$status")

    while read -r online dns; do
      [ -n "$dns" ] || continue
      url="https://$dns:${port}"
      expires=$(jq -r --arg u "$url" '[.[] | select(.urls | index($u))][0].expiresAt // empty' <<<"$links")
      if [ -n "$expires" ] && [ "$(date -d "$expires" +%s)" -gt "$renew_before" ]; then
        echo "$dns: linked until $expires"
        continue
      fi
      if [ "$online" != true ]; then
        echo "$dns: offline, linking when it is back"
        continue
      fi
      code=$(ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
        "${cfg.user}@$dns" \
        '/run/current-system/sw/bin/t3 auth pairing create --ttl 5m --label "fleet link from ${config.networking.hostName}" --json' \
        | jq -r '.credential // empty')
      if [ -z "$code" ]; then
        echo "$dns: could not get a pairing code over SSH"
        failed=1
        continue
      fi
      if ${t3} environment link "$url" --pairing-code "$code" --access ${cfg.access} </dev/null; then
        echo "$dns: linked"
      else
        echo "$dns: link failed"
        failed=1
      fi
    done <<<"$members"

    # Forget fleet links (tailnet T3 addresses) to machines no longer tagged.
    fleet_urls=$(awk -v p=${port} 'NF { printf "https://%s:%s\n", $2, p }' <<<"$members" | jq -R . | jq -s .)
    while read -r id; do
      [ -n "$id" ] || continue
      echo "unlinking $id: no longer in the fleet"
      ${t3} environment unlink "$id" </dev/null || failed=1
    done < <(jq -r --arg sfx ".$suffix:${port}" --argjson fleet "$fleet_urls" \
      '.[] | select(any(.urls[]; endswith($sfx))) | select(all(.urls[]; . as $u | $fleet | index($u) | not)) | .environmentId' \
      <<<"$links")

    exit $failed
  '';
in
lib.mkIf cfg.hub {
  systemd.user.services.t3-fleet-link = {
    description = "Link every fleet machine to this T3 Code";
    after = [ "t3code.service" ];
    unitConfig.ConditionUser = cfg.user;
    path = [ config.services.tailscale.package pkgs.openssh pkgs.jq pkgs.gawk pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${linkFleet}";
    };
  };
  systemd.user.timers.t3-fleet-link = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = cfg.user;
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "6h";
    };
  };
}
