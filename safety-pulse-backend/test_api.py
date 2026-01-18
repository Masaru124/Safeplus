#!/usr/bin/env python3
"""
Test script for Safety Pulse Backend API
Run this after starting the backend with docker-compose up
"""

import requests
import json
import time
import hashlib

BASE_URL = "http://localhost:8000"

def hash_device_id(device_id: str) -> str:
    """Generate device hash as the app would"""
    return hashlib.sha256(device_id.encode()).hexdigest()

def test_health():
    """Test health endpoint"""
    print("Testing /health endpoint...")
    response = requests.get(f"{BASE_URL}/health")
    print(f"Status: {response.status_code}")
    print(f"Response: {response.json()}")
    assert response.status_code == 200
    print("✓ Health check passed\n")

def test_report_signal():
    """Test reporting a safety signal"""
    print("Testing POST /api/v1/report...")

    device_id = "test-device-001"
    device_hash = hash_device_id(device_id)

    payload = {
        "signal_type": "followed",
        "severity": 4,
        "latitude": 12.9716,
        "longitude": 77.5946,
        "context": {
            "time": "night",
            "alone": True
        }
    }

    headers = {
        "Content-Type": "application/json",
        "X-Device-Hash": device_hash
    }

    response = requests.post(
        f"{BASE_URL}/api/v1/report",
        json=payload,
        headers=headers
    )

    print(f"Status: {response.status_code}")
    print(f"Response: {response.json()}")

    if response.status_code == 200:
        print("✓ Signal report successful\n")
        return True
    else:
        print("✗ Signal report failed\n")
        return False

def test_get_pulse():
    """Test getting safety pulse data"""
    print("Testing GET /api/v1/pulse...")

    params = {
        "lat": 12.9716,
        "lng": 77.5946,
        "radius": 10,
        "time_window": "24h"
    }

    response = requests.get(f"{BASE_URL}/api/v1/pulse", params=params)

    print(f"Status: {response.status_code}")
    print(f"Response: {response.json()}")

    if response.status_code == 200:
        print("✓ Pulse data retrieval successful\n")
        return True
    else:
        print("✗ Pulse data retrieval failed\n")
        return False

def test_rate_limiting():
    """Test rate limiting"""
    print("Testing rate limiting...")

    device_id = "test-device-rate-limit"
    device_hash = hash_device_id(device_id)

    payload = {
        "signal_type": "harassment",
        "severity": 5,
        "latitude": 12.9716,
        "longitude": 77.5946,
        "context": {"time": "night", "alone": True}
    }

    headers = {
        "Content-Type": "application/json",
        "X-Device-Hash": device_hash
    }

    # Send multiple requests quickly
    for i in range(15):
        response = requests.post(
            f"{BASE_URL}/api/v1/report",
            json=payload,
            headers=headers
        )
        if response.status_code == 429:
            print(f"✓ Rate limiting triggered after {i+1} requests")
            return True
        time.sleep(0.1)  # Small delay between requests

    print("✗ Rate limiting not triggered")
    return False

def test_invalid_signal_type():
    """Test invalid signal type validation"""
    print("Testing invalid signal type...")

    device_hash = hash_device_id("test-device-invalid")

    payload = {
        "signal_type": "invalid_type",
        "severity": 3,
        "latitude": 12.9716,
        "longitude": 77.5946,
        "context": {}
    }

    headers = {
        "Content-Type": "application/json",
        "X-Device-Hash": device_hash
    }

    response = requests.post(
        f"{BASE_URL}/api/v1/report",
        json=payload,
        headers=headers
    )

    print(f"Status: {response.status_code}")
    print(f"Response: {response.json()}")

    if response.status_code == 400:
        print("✓ Invalid signal type properly rejected\n")
        return True
    else:
        print("✗ Invalid signal type not rejected\n")
        return False

def main():
    """Run all tests"""
    print("🛡️  Safety Pulse Backend API Tests\n")

    try:
        # Wait for services to be ready
        print("Waiting for services to start...")
        time.sleep(5)

        # Run tests
        test_health()
        test_invalid_signal_type()

        if test_report_signal():
            test_get_pulse()

        test_rate_limiting()

        print("🎉 All tests completed!")

    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to backend. Make sure it's running with:")
        print("   docker-compose up")
    except Exception as e:
        print(f"❌ Test failed with error: {e}")

if __name__ == "__main__":
    main()
