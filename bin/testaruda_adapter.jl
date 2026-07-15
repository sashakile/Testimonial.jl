#!/usr/bin/env julia
# testaruda-adapter — Adapter protocol entry point for testaruda integration.
#
# Spawned by testaruda as a subprocess. Reads JSON commands from stdin,
# responds on stdout. Diagnostics go to stderr.
#
# Per PROTO-001, this is a thin wrapper around Testimonial.run_adapter_protocol().

import Testimonial
using Testimonial.Protocol

Testimonial.Protocol.run_adapter_protocol()