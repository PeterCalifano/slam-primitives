#!/bin/bash
# Quick bash script to automate debug sessions using cmake + gdb
# Created by PeterC 05-04-2024

arg=$1 # Get input path from VSCode as arg1
buildpath=$arg/debug

echo "Target path: $buildpath"

if  ! [ -d $buildpath ]; then
    cmake -S . -B $buildpath -DCMAKE_BUILD_TYPE=DEBUG 
    #cd $buildpath
else
    echo "$buildpath already exists"
    #cd $buildpath
    #make clean
fi

make -j2 -C $buildpath
echo "File build: $2"
