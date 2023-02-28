#!/usr/bin/env bash
user=${1:-'16201230'}
collection=${2:-'What-I-want-on-Fenix'}
nextURL="https://services.addons.mozilla.org/api/v4/accounts/account/$user/collections/$collection/addons/?page_size=50&sort=-popularity&lang=en-US"
while [[ -n "$nextURL" && "$nextURL" != null ]]; do
	jsonBlock="$(curl -s --location "$nextURL")"
	nextURL="$(jq -r .next <<< "$jsonBlock")"
	printf '%s\n' "$jsonBlock"
done | jq --slurp '.[0] + {page_count: 1, page_size: .[0].count, next: null, results: [.[].results[]]}'
