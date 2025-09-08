#!/usr/bin/env python3
"""
HTTP Server for NFC Reader LLM Service
影聲 NFC 讀取器 HTTP 服務器

This server provides HTTP API endpoints for LLM chat functionality,
replacing the WebSocket implementation for better reliability and scalability.
"""

import asyncio
import json
import logging
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
import uuid
import time
import hashlib
from enum import Enum

# Import required services
from cached_feishu_service import CachedFeishuService
from gemini_service import GeminiService
from character_prompts import (
    set_feishu_service, 
    get_character_name, 
    get_character_voice_id, 
    get_available_characters
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="影聲 NFC Reader HTTP API",
    description="HTTP API server for NFC Reader LLM chat functionality",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
feishu_service = CachedFeishuService()

# Set the shared service instance for character_prompts
set_feishu_service(feishu_service)

# Initialize Gemini service with shared Feishu service
gemini_service = GeminiService()

# In-memory storage for demo purposes
# In production, use a proper database
chat_sessions: Dict[str, Dict[str, Any]] = {}
recent_messages: Dict[str, float] = {}

# Pydantic models for request/response
class ChatRequest(BaseModel):
    type: str
    text: str
    character_id: Optional[int] = None
    streaming: Optional[bool] = False
    connection_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    voice_id: Optional[str] = None
    character_id: Optional[int] = None
    character_name: Optional[str] = None
    success: bool
    error: Optional[str] = None
    timestamp: Optional[str] = None

class CharacterRequest(BaseModel):
    character_id: int

class CharacterResponse(BaseModel):
    character_id: int
    character_name: str
    voice_id: str
    success: bool
    error: Optional[str] = None

class ClearHistoryResponse(BaseModel):
    success: bool
    message: str
    error: Optional[str] = None

class PingResponse(BaseModel):
    success: bool
    message: str
    timestamp: str

class HistoryResponse(BaseModel):
    messages: List[Dict[str, Any]]
    success: bool
    error: Optional[str] = None

class CharactersResponse(BaseModel):
    characters: List[Dict[str, Any]]
    current_character_id: int
    current_character_name: str
    success: bool
    error: Optional[str] = None

class CharacterMapResponse(BaseModel):
    character_map: Dict[str, Any]
    success: bool
    error: Optional[str] = None

class CacheStatusResponse(BaseModel):
    cache_info: Dict[str, Any]
    success: bool
    error: Optional[str] = None

class TTSRequest(BaseModel):
    type: str
    text: str
    character_id: int

class TTSResponse(BaseModel):
    type: str
    text: str
    character_id: int
    character_name: str
    voice_id: str
    message: str
    timestamp: str
    success: bool
    error: Optional[str] = None

# Helper functions
def get_or_create_session(connection_id: str) -> Dict[str, Any]:
    """Get or create chat session for connection"""
    if connection_id not in chat_sessions:
        chat_sessions[connection_id] = {
            "messages": [],
            "character_id": 1,
            "created_at": datetime.now()
        }
    return chat_sessions[connection_id]

def is_duplicate_message(client_id: str, message_type: str, message_data: Dict[str, Any]) -> bool:
    """Check if message is duplicate"""
    # Generate message hash
    message_hash = hashlib.md5(json.dumps(message_data, sort_keys=True).encode()).hexdigest()
    message_key = f"{client_id}_{message_type}_{message_hash}"
    current_time = time.time()
    
    # Check if duplicate within 1 second
    if message_key in recent_messages:
        if current_time - recent_messages[message_key] < 1.0:
            return True
    
    # Store message time
    recent_messages[message_key] = current_time
    
    # Clean old messages (keep last 100)
    if len(recent_messages) > 100:
        old_keys = sorted(recent_messages.keys(), key=lambda k: recent_messages[k])[:50]
        for key in old_keys:
            del recent_messages[key]
    
    return False

@app.get("/")
async def root():
    """Health check endpoint"""
    return {"message": "影聲 NFC Reader HTTP API Server", "status": "running"}

@app.get("/api/ping")
async def ping():
    """Ping endpoint for connection testing"""
    return PingResponse(
        success=True,
        message="Server is running",
        timestamp=datetime.now().isoformat()
    )

@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Main chat endpoint for LLM queries"""
    try:
        logger.info(f"Received chat request: {request.type} - {request.text[:50]}...")
        
        # Check for duplicate messages
        client_id = request.connection_id or "anonymous"
        message_data = {
            "type": request.type,
            "text": request.text,
            "character_id": request.character_id
        }
        
        if is_duplicate_message(client_id, request.type, message_data):
            logger.warning(f"Duplicate message detected: {request.type}")
            return ChatResponse(
                response="",
                success=False,
                error="Duplicate message"
            )
        
        # Get or create session
        if request.connection_id:
            session = get_or_create_session(request.connection_id)
            if request.character_id:
                session["character_id"] = request.character_id
        else:
            # Generate temporary session ID
            temp_id = str(uuid.uuid4())
            session = get_or_create_session(temp_id)
            if request.character_id:
                session["character_id"] = request.character_id
        
        # Store user message
        user_message = {
            "text": request.text,
            "is_user": True,
            "timestamp": datetime.now().isoformat(),
            "is_error": False
        }
        session["messages"].append(user_message)
        
        # Generate LLM response
        if request.type in ["text", "gemini_chat"]:
            logger.info(f"🔍 DEBUG: request.character_id = {request.character_id}")
            logger.info(f"🔍 DEBUG: gemini_service current character BEFORE = {gemini_service.get_current_character_id()}")
            
            # 強制更新 Gemini Service 嘅當前角色
            if request.character_id and request.character_id != gemini_service.get_current_character_id():
                logger.info(f"🔧 DEBUG: Force updating gemini_service character from {gemini_service.get_current_character_id()} to {request.character_id}")
                gemini_service.set_character(request.character_id)
            
            logger.info(f"🔍 DEBUG: gemini_service current character AFTER = {gemini_service.get_current_character_id()}")
            
            response_text = await gemini_service.send_message(
                message=request.text, 
                include_context=True, 
                character_id=request.character_id
            )
            
            # Get character info
            character_id = request.character_id or gemini_service.get_current_character_id()
            character_name = get_character_name(character_id)
            voice_id = get_character_voice_id(character_id)
            
            # Store AI response
            ai_message = {
                "text": response_text,
                "is_user": False,
                "timestamp": datetime.now().isoformat(),
                "is_error": False
            }
            session["messages"].append(ai_message)
            
            return ChatResponse(
                response=response_text,
                voice_id=voice_id,
                character_id=character_id,
                character_name=character_name,
                success=True,
                timestamp=datetime.now().isoformat()
            )
            
        else:
            raise HTTPException(status_code=400, detail=f"Unsupported message type: {request.type}")
            
    except Exception as e:
        logger.error(f"Chat request failed: {str(e)}")
        return ChatResponse(
            response="",
            success=False,
            error=str(e)
        )

@app.post("/api/character", response_model=CharacterResponse)
async def get_character_info(request: CharacterRequest):
    """Get character information"""
    try:
        character_name = get_character_name(request.character_id)
        voice_id = get_character_voice_id(request.character_id)
        
        if character_name and character_name != "AI 助手":
            return CharacterResponse(
                character_id=request.character_id,
                character_name=character_name,
                voice_id=voice_id,
                success=True
            )
        else:
            return CharacterResponse(
                character_id=request.character_id,
                character_name="未知角色",
                voice_id="moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
                success=False,
                error="Character not found"
            )
            
    except Exception as e:
        logger.error(f"Character request failed: {str(e)}")
        return CharacterResponse(
            character_id=request.character_id,
            character_name="錯誤",
            voice_id="moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
            success=False,
            error=str(e)
        )

@app.get("/api/history", response_model=HistoryResponse)
async def get_history(connection_id: Optional[str] = None):
    """Get chat history"""
    try:
        if connection_id and connection_id in chat_sessions:
            session = chat_sessions[connection_id]
            return HistoryResponse(
                messages=session["messages"],
                success=True
            )
        else:
            # Return Gemini service history if no session
            gemini_history = gemini_service.get_history()
            return HistoryResponse(
                messages=gemini_history,
                success=True
            )
            
    except Exception as e:
        logger.error(f"History request failed: {str(e)}")
        return HistoryResponse(
            messages=[],
            success=False,
            error=str(e)
        )

@app.post("/api/history/clear", response_model=ClearHistoryResponse)
async def clear_history(connection_id: Optional[str] = None):
    """Clear chat history"""
    try:
        if connection_id and connection_id in chat_sessions:
            chat_sessions[connection_id]["messages"] = []
            message = "Session history cleared successfully"
        else:
            # Clear all sessions and Gemini history
            chat_sessions.clear()
            gemini_service.clear_history()
            message = "All history cleared successfully"
            
        return ClearHistoryResponse(
            success=True,
            message=message
        )
        
    except Exception as e:
        logger.error(f"Clear history failed: {str(e)}")
        return ClearHistoryResponse(
            success=False,
            message="Failed to clear history",
            error=str(e)
        )

@app.get("/api/characters", response_model=CharactersResponse)
async def list_characters():
    """List all available characters"""
    try:
        characters_dict = gemini_service.get_available_characters()
        
        # Convert dictionary to list of character objects
        characters = [
            {"character_id": char_id, "character_name": char_name}
            for char_id, char_name in characters_dict.items()
        ]
        
        return CharactersResponse(
            characters=characters,
            current_character_id=gemini_service.get_current_character_id(),
            current_character_name=gemini_service.get_current_character(),
            success=True
        )
        
    except Exception as e:
        logger.error(f"List characters failed: {str(e)}")
        return CharactersResponse(
            characters=[],
            current_character_id=1,
            current_character_name="AI 助手",
            success=False,
            error=str(e)
        )

@app.post("/api/character/set")
async def set_character(request: CharacterRequest):
    """Set current character"""
    try:
        character_id = request.character_id
        
        # Check if character exists
        if character_id not in get_available_characters():
            return {
                "success": False,
                "error": f"Character {character_id} not found"
            }
        
        # Set character in Gemini service
        gemini_service.set_character(character_id)
        
        return {
            "type": "character_set",
            "character_id": gemini_service.get_current_character_id(),
            "character_name": gemini_service.get_current_character(),
            "message": f"Character set to: {gemini_service.get_current_character()} (ID: {gemini_service.get_current_character_id()})",
            "success": True
        }
        
    except Exception as e:
        logger.error(f"Set character failed: {str(e)}")
        return {
            "success": False,
            "error": str(e)
        }

@app.get("/api/character/map", response_model=CharacterMapResponse)
async def get_character_map():
    """Get character map for iPhone app"""
    try:
        character_map = get_available_characters()
        
        # Convert integer keys to string keys for JSON compatibility
        character_map_str = {str(k): v for k, v in character_map.items()}
        
        return CharacterMapResponse(
            character_map=character_map_str,
            success=True
        )
        
    except Exception as e:
        logger.error(f"Get character map failed: {str(e)}")
        return CharacterMapResponse(
            character_map={},
            success=False,
            error=str(e)
        )

@app.get("/api/character/name")
async def get_character_name_endpoint(character_id: int):
    """Get character name by ID for iPhone app"""
    try:
        if character_id is None:
            return {
                "success": False,
                "error": "character_id is required"
            }
        
        character_name = get_character_name(character_id)
        
        return {
            "type": "character_name",
            "character_id": character_id,
            "character_name": character_name,
            "success": True
        }
        
    except Exception as e:
        logger.error(f"Get character name failed: {str(e)}")
        return {
            "success": False,
            "error": str(e)
        }

@app.get("/api/cache/status", response_model=CacheStatusResponse)
async def get_cache_status():
    """Get cache status for debugging"""
    try:
        cache_info = feishu_service.get_cache_info()
        
        return CacheStatusResponse(
            cache_info=cache_info,
            success=True
        )
        
    except Exception as e:
        logger.error(f"Get cache status failed: {str(e)}")
        return CacheStatusResponse(
            cache_info={},
            success=False,
            error=str(e)
        )

@app.post("/api/tts", response_model=TTSResponse)
async def text_to_speech(request: TTSRequest):
    """Text-to-speech endpoint (iPhone handles actual TTS)"""
    try:
        if not request.text:
            return TTSResponse(
                type="error",
                text="",
                character_id=0,
                character_name="",
                voice_id="",
                message="text is required for text_to_speech request",
                timestamp=datetime.now().isoformat(),
                success=False,
                error="text is required"
            )
        
        # Get character info
        character_name = get_character_name(request.character_id)
        voice_id = get_character_voice_id(request.character_id)
        
        logger.info(f"TTS request: text={request.text[:30]}..., character_id={request.character_id}")
        
        return TTSResponse(
            type="tts_info",
            text=request.text,
            character_id=request.character_id,
            character_name=character_name,
            voice_id=voice_id,
            message="TTS should be handled on iPhone side",
            timestamp=datetime.now().isoformat(),
            success=True
        )
        
    except Exception as e:
        logger.error(f"TTS request failed: {str(e)}")
        return TTSResponse(
            type="error",
            text="",
            character_id=0,
            character_name="",
            voice_id="",
            message="TTS request failed",
            timestamp=datetime.now().isoformat(),
            success=False,
            error=str(e)
        )

# Error handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": exc.detail}
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={"success": False, "error": "Internal server error"}
    )

if __name__ == "__main__":
    # Configuration
    HOST = "145.79.12.177"
    PORT = 10000  # Use different port to avoid conflict with WebSocket server
    
    logger.info(f"Starting HTTP server on {HOST}:{PORT}")
    logger.info("影聲 NFC Reader HTTP API Server")
    logger.info("Available endpoints:")
    logger.info("  GET  /                 - Health check")
    logger.info("  GET  /api/ping        - Connection test")
    logger.info("  POST /api/chat         - LLM chat (text/gemini_chat)")
    logger.info("  POST /api/character    - Get character info")
    logger.info("  POST /api/character/set - Set current character")
    logger.info("  GET  /api/character/map - Get character map")
    logger.info("  GET  /api/character/name - Get character name")
    logger.info("  GET  /api/characters   - List all characters")
    logger.info("  GET  /api/history      - Get chat history")
    logger.info("  POST /api/history/clear - Clear history")
    logger.info("  POST /api/tts          - Text-to-speech info")
    logger.info("  GET  /api/cache/status - Cache status")
    
    # Run the server
    uvicorn.run(
        "http_server:app",  # Use import string for reload support
        host=HOST,
        port=PORT,
        log_level="info",
        reload=True  # Enable for development
    )