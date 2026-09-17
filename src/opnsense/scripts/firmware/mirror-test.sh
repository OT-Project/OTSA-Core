#!/bin/sh

# Copyright (C) 2026 KC01.04-21.30 <bkcs@hust.edu.vn>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# configd wrapper for `otsa-test-mirror`. Receives the candidate mirror URL
# from the API caller (e.g. Firmware Settings "Test" button) and forwards the
# raw JSON output produced by the CLI tool. The URL is validated by the API
# layer before reaching configd.

URL=$1
TOOL=/usr/local/sbin/otsa-test-mirror

if [ -z "${URL}" ]; then
    echo '{"status":"failure","step":"input","message":"mirror URL missing"}'
    exit 0
fi

# Guard against missing tool — without this the wrapper exits non-zero with
# no stdout, and the API controller falls through to step=parse with an
# empty `raw` field, which is hard to debug from the UI.
if [ ! -x "${TOOL}" ]; then
    printf '{"status":"failure","step":"tool","message":"%s not installed (install os-update package)"}\n' "${TOOL}"
    exit 0
fi

exec "${TOOL}" "${URL}"
