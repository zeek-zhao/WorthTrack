#!/usr/bin/env bash
P="$HOME/.pub-cache/hosted/pub.dev"
sed -n '360,440p' "$P/drift_dev-2.29.0/lib/src/analysis/resolver/dart/column.dart"
