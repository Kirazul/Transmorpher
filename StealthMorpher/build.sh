#!/bin/bash

echo "========================================"
echo "Building StealthMorpher DLL"
echo "========================================"
echo ""

# Check if build directory exists
if [ ! -d "build" ]; then
    echo "Creating build directory..."
    mkdir build
fi

cd build

echo "Running CMake configuration..."
cmake .. -DCMAKE_BUILD_TYPE=Release
if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: CMake configuration failed!"
    echo "Make sure you have CMake and a C++ compiler installed."
    exit 1
fi

echo ""
echo "Building Release configuration..."
cmake --build . --config Release
if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Build failed!"
    exit 1
fi

echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo ""
echo "The compiled DLL is located at:"
echo "$(pwd)/Release/dinput8.dll"
echo ""
echo "Copy this file to your WoW directory to use the updated morpher."
echo ""
