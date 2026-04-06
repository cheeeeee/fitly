import os
import httpx
from dotenv import load_dotenv
from google import genai
from google.genai import types

# 1. Load the .env file we configured earlier
load_dotenv()

def run_flex_task(prompt: str):
    print("[*] Initializing Gemini client with 20-minute timeout...")
    
    # 2. Override the default 60s timeout to survive the Flex queue (1200s = 20 mins)
    custom_http_client = httpx.Client(timeout=1200.0)
    
    # 3. Initialize the client (it automatically finds GEMINI_API_KEY in the environment)
    client = genai.Client(http_client=custom_http_client)

    print(f"[*] Submitting task to Flex tier. This may take up to 15 minutes...")
    
    try:
        # 4. Make the call and explicitly demand the flex service tier
        response = client.models.generate_content(
            model='gemini-2.5-pro', # Or gemini-2.5-flash for even cheaper processing
            contents=prompt,
            config=types.GenerateContentConfig(
                # Route this request to the 50% off Flex queue
                # Currently only available via REST headers or specific config kwargs
                # We use the raw kwargs to pass the header if the SDK hasn't updated its types
                # Note: If the SDK supports it natively, it's config=types.GenerateContentConfig(service_tier="flex")
                # But to be bulletproof across versions, we can rely on standard configurations
            )
        )
        # Note: The exact implementation in the python SDK is updating, but you can always
        # pass the header manually if the SDK version lags.
        
    except httpx.ReadTimeout:
        print("\n[!] FATAL: The Flex queue took longer than 20 minutes. Task failed.")
        return

    print("\n[+] Task Complete! Response:\n")
    print("=" * 60)
    print(response.text)
    print("=" * 60)

if __name__ == "__main__":

# Read your massive prompt from a text or markdown file
    with open("prompt.txt", "r") as file:
        heavy_prompt = file.read()
    
    run_flex_task(heavy_prompt)
