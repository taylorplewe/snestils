#!/bin/bash

{
  head -c 512 /dev/zero
  cat "$1"
} > new.sfc
