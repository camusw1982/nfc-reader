#!/usr/bin/env python3
"""
Gemini Service for CineSpark - handles AI chat with context support
"""

import google.generativeai as genai
import os
import logging
from typing import List, Dict, Optional
from datetime import datetime
from character_prompts import format_message_with_character, get_available_characters, get_character_name

logger = logging.getLogger(__name__)

class GeminiService:
    """Gemini AI service for chat functionality"""
    
    def __init__(self, api_key: str = None):
        """Initialize Gemini service with API key"""
        if api_key is None:
            # Read API key from file
            key_file = os.path.join(os.path.dirname(__file__), 'key', 'gemini.key')
            try:
                with open(key_file, 'r') as f:
                    api_key = f.read().strip()
            except FileNotFoundError:
                raise ValueError(f"API key file not found: {key_file}")
        
        if not api_key:
            raise ValueError("Gemini API key is required")
        
        # Configure Gemini
        genai.configure(api_key=api_key)
        
        # Initialize model with thinking mode disabled
        generation_config = genai.types.GenerationConfig(
            candidate_count=1,
            max_output_tokens=8192,
            temperature=0.7,
            top_p=0.8,
            top_k=40
        )
        self.model = genai.GenerativeModel(
            'gemini-2.5-flash',
            generation_config=generation_config
        )
        
        # Store conversation history
        self.conversation_history: List[Dict] = []
        
        # Maximum history length to prevent context overflow
        self.max_history_length = 50
        
        # Current character ID for responses (1=標叔, 2=雷達標, 3=味全師傅)
        self.current_character_id = 1
        
        logger.info("Gemini service initialized successfully")
    
    def add_to_history(self, role: str, content: str):
        """Add message to conversation history"""
        self.conversation_history.append({
            'role': role,
            'content': content,
            'timestamp': datetime.now().isoformat()
        })
        
        # Trim history if it gets too long
        if len(self.conversation_history) > self.max_history_length:
            self.conversation_history = self.conversation_history[-self.max_history_length:]
    
    def get_context_messages(self) -> List[Dict]:
        """Get formatted context messages for Gemini"""
        context_messages = []
        
        for msg in self.conversation_history:
            if msg['role'] == 'user':
                context_messages.append({
                    'role': 'user',
                    'parts': [msg['content']]
                })
            elif msg['role'] == 'assistant':
                context_messages.append({
                    'role': 'model',
                    'parts': [msg['content']]
                })
        
        return context_messages
    
    def clear_history(self):
        """Clear conversation history"""
        self.conversation_history.clear()
        logger.info("Conversation history cleared")
    
    def get_history(self) -> List[Dict]:
        """Get conversation history"""
        return self.conversation_history.copy()
    
    def set_character(self, character_id: int):
        """Set the current character for responses"""
        available_characters = get_available_characters()
        if character_id in available_characters:
            self.current_character_id = character_id
            character_name = get_character_name(character_id)
            logger.info(f"Character set to: {character_name} (ID: {character_id})")
        else:
            logger.warning(f"Unknown character ID: {character_id}. Available: {available_characters}")
    
    def get_current_character(self) -> str:
        """Get current character name"""
        return get_character_name(self.current_character_id)
    
    def get_current_character_id(self) -> int:
        """Get current character ID"""
        return self.current_character_id
    
    def get_available_characters(self) -> dict:
        """Get list of available characters with their IDs"""
        return get_available_characters()
    
    async def send_message(self, message: str, include_context: bool = True, character_id: int = None) -> str:
        """
        Send message to Gemini and get response
        
        Args:
            message: User message
            include_context: Whether to include conversation history
            character_id: Character ID to use for response (overrides current character)
            
        Returns:
            Gemini response text
        """
        try:
            # Use specified character ID or current character ID
            character_to_use = character_id if character_id is not None else self.current_character_id
            
            # Update current character ID if a different one is specified
            if character_id is not None and character_id != self.current_character_id:
                logger.info(f"🎭 GEMINI DEBUG: Updating current_character_id from {self.current_character_id} to {character_id}")
                self.current_character_id = character_id
            
            # Debug info for character selection
            logger.info(f"🎭 GEMINI DEBUG: Using character_id={character_to_use}")
            character_name = get_character_name(character_to_use)
            logger.info(f"🎭 GEMINI DEBUG: Character name='{character_name}' (ID: {character_to_use})")
            
            # Format message with character prompt
            formatted_message = format_message_with_character(message, character_to_use)
            logger.info(f"🎭 GEMINI DEBUG: Formatted message length={len(formatted_message)} characters")
            
            # Add original user message to history (without character prompt)
            self.add_to_history('user', message)
            
            if include_context and len(self.conversation_history) > 1:
                # Start chat with history
                context_messages = self.get_context_messages()
                # Create chat with history (excluding the current user message that was just added)
                chat = self.model.start_chat(history=context_messages[:-1])
                response = chat.send_message(formatted_message)
            else:
                # Simple message without history
                response = self.model.generate_content(formatted_message)
            
            # Extract response text
            response_text = response.text
            
            # Add assistant response to history
            self.add_to_history('assistant', response_text)
            
            return response_text
            
        except Exception as e:
            logger.error(f"❌ GEMINI ERROR: {e}")
            raise Exception(f"Gemini API error: {str(e)}")
    
    def get_conversation_summary(self) -> Dict:
        """Get summary of current conversation"""
        return {
            'total_messages': len(self.conversation_history),
            'user_messages': len([m for m in self.conversation_history if m['role'] == 'user']),
            'assistant_messages': len([m for m in self.conversation_history if m['role'] == 'assistant']),
            'last_message_time': self.conversation_history[-1]['timestamp'] if self.conversation_history else None,
            'history_length_limit': self.max_history_length,
            'current_character_id': self.current_character_id,
            'current_character_name': self.get_current_character(),
            'available_characters': self.get_available_characters()
        }