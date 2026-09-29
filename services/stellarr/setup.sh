#!/usr/bin/env bash
# Stellarr service setup — sourced by setup.sh
# Expects: info function available in caller

# Retire the old ratio-based deletion job on existing hosts.
rm -f /etc/cron.d/transmission-cleanup
info "Removed retired Transmission cleanup cron job"
