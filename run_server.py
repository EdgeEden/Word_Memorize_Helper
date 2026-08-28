import sys
import os

# Add server directory to path
server_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server")
sys.path.insert(0, server_dir)

import uvicorn

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    print(f"==================================================")
    print(f"  WordN FastAPI Cloud Sync Backend Server")
    print(f"  Listening on: http://0.0.0.0:{port}")
    print(f"  Swagger Docs: http://127.0.0.1:{port}/docs")
    print(f"==================================================")
    uvicorn.run("main:app", app_dir=server_dir, host="0.0.0.0", port=port, reload=True)

