#!/usr/bin/env bash
set -euo pipefail

base_created="${1:?base image creation time is required}"
published_created="${2:?published image creation time is required}"
now="${3:-$(date -u +%s)}"

base_epoch="$(date -u -d "$base_created" +%s)"
published_epoch="$(date -u -d "$published_created" +%s)"

(( base_epoch > published_epoch || now - published_epoch >= 14 * 24 * 60 * 60 ))
