#!/usr/bin/env python3
"""
HTTP API Server for CineSpark - handles Character ID validation from iPhone app
"""

from flask import Flask, jsonify, request
import logging
import sys
import os
from feishu_service import FeishuService

# Add current directory to path to import modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Initialize Feishu service
try:
    feishu_service = FeishuService()
    logger.info("Feishu service initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Feishu service: {e}")
    feishu_service = None

@app.route('/api/validate-character/<character_id>', methods=['GET'])
def validate_character(character_id):
    """Validate Character ID and return character data"""
    try:
        if not feishu_service:
            return jsonify({
                "success": False,
                "message": "Feishu service not available"
            }), 500
        
        # Convert character_id to integer
        try:
            char_id = int(character_id)
        except ValueError:
            return jsonify({
                "success": False,
                "message": "Character ID must be a number"
            }), 400
        
        logger.info(f"Validating character ID: {char_id}")
        
        # Get character data from Feishu
        character_data = feishu_service.get_character_full_data(char_id)
        
        if character_data:
            # Character found
            response_data = {
                "success": True,
                "message": "Character ID validated successfully",
                "data": {
                    "character_id": character_data.get("character_id"),
                    "name": character_data.get("name", f"Character {char_id}"),
                    "prompt": character_data.get("prompt", ""),
                    "voice_id": character_data.get("voice_id", "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"),
                    "available": character_data.get("available", True)
                }
            }
            
            logger.info(f"Character {char_id} validated successfully")
            return jsonify(response_data)
        else:
            # Character not found
            logger.warning(f"Character {char_id} not found")
            return jsonify({
                "success": False,
                "message": f"Character ID {char_id} not found"
            }), 404
            
    except Exception as e:
        logger.error(f"Error validating character {character_id}: {e}")
        return jsonify({
            "success": False,
            "message": f"Server error: {str(e)}"
        }), 500

@app.route('/api/character/<character_id>', methods=['GET'])
def get_character(character_id):
    """Get character data by ID"""
    try:
        if not feishu_service:
            return jsonify({
                "success": False,
                "message": "Feishu service not available"
            }), 500
        
        # Convert character_id to integer
        try:
            char_id = int(character_id)
        except ValueError:
            return jsonify({
                "success": False,
                "message": "Character ID must be a number"
            }), 400
        
        logger.info(f"Getting character data for ID: {char_id}")
        
        # Get character data from Feishu
        character_data = feishu_service.get_character_full_data(char_id)
        
        if character_data:
            response_data = {
                "success": True,
                "data": {
                    "character_id": character_data.get("character_id"),
                    "name": character_data.get("name", f"Character {char_id}"),
                    "prompt": character_data.get("prompt", ""),
                    "voice_id": character_data.get("voice_id", "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"),
                    "available": character_data.get("available", True)
                }
            }
            
            logger.info(f"Character data retrieved for {char_id}")
            return jsonify(response_data)
        else:
            logger.warning(f"Character {char_id} not found")
            return jsonify({
                "success": False,
                "message": f"Character ID {char_id} not found"
            }), 404
            
    except Exception as e:
        logger.error(f"Error getting character {character_id}: {e}")
        return jsonify({
            "success": False,
            "message": f"Server error: {str(e)}"
        }), 500

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "feishu_service": "available" if feishu_service else "unavailable"
    })

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        "service": "CineSpark API Server",
        "version": "1.0.0",
        "endpoints": [
            "GET /api/validate-character/<character_id>",
            "GET /api/character/<character_id>",
            "GET /api/health"
        ]
    })

if __name__ == '__main__':
    # Run HTTP server on port 10000
    logger.info("Starting HTTP API server on port 10000")
    app.run(host='145.79.12.177', port=10000, debug=True)