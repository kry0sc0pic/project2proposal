import requests
import socketio
import json
import time

def test_budget_scraping():
    # Initialize Socket.IO client
    sio = socketio.Client()
    
    # # Define Socket.IO event handlers
    # @sio.event
    # def connect():
    #     print("Connected to server")
    
    # @sio.event
    # def disconnect():
    #     print("Disconnected from server")
    
    @sio.on('complete')
    def on_complete(data):
        print("Scraping completed!")
        print("Results:", json.dumps(data['results'], indent=2))
        sio.disconnect()
    
    @sio.on('scrape_error')
    def on_error(data):
        print("Error occurred:", data['error'])
        sio.disconnect()
    
    @sio.on('join_success')
    def on_join_success(data):
        print("Successfully joined task room:", data['task_id'])
    
    # Test URLs to scrape
    test_urls = [
        "https://www.amazon.in/Raspberry-Pi-4-Model-8GB/dp/B0899VXM8F",
        "https://robu.in/product/raspberry-pi-4-model-b-with-8gb-ram/"
    ]
    
    # Make the initial HTTP request
    server_url = "http://localhost:45767"
    response = requests.post(
        f"{server_url}/scrape_info",
        json={"links": test_urls}
    )
    
    if response.status_code == 200:
        task_id = response.json()['task_id']
        print("Task ID received:", task_id)
        # Connect to WebSocket
        try:
            sio.connect(server_url)
            sio.emit('join_task', {'task_id': task_id})
            
            # Wait for results (timeout after 60 seconds)
            timeout = 60
            start_time = time.time()
            while sio.connected and (time.time() - start_time) < timeout:
                time.sleep(1)
            
            if sio.connected:
                print("Timeout reached")
                sio.disconnect()
                
        except Exception as e:
            print("Error connecting to WebSocket:", str(e))
    else:
        print("Error making initial request:", response.status_code)

if __name__ == "__main__":
    test_budget_scraping()
