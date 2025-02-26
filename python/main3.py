from markdown_pdf import MarkdownPdf, Section
import os
from flask import Flask, send_file, request, jsonify
import asyncio
from browser_use import BrowserConfig, Browser, Agent
from langchain_openai import ChatOpenAI
import uuid
from threading import Thread
from flask_cors import CORS
import json
from asyncio import Semaphore

app = Flask(__name__)
CORS(app,origins="*")

# Store ongoing scraping tasks and results
scraping_tasks = {}
scraping_results = {}
# Limit concurrent jobs to 10
scraping_semaphore = Semaphore(10)

@app.route('/md2pdf', methods=['POST'])
def make_pdf():
    # Get the uploaded file from the request
    markdown_content = request.get_json()['markdown']
    pdf = MarkdownPdf()
    pdf.add_section(section=Section(markdown_content,toc=False))
    pdf.meta["title"] = "Proposal"
    pdf.meta["author"] = "Project2Proposal"
    # Create an in-memory bytes buffer to store the PDF
    pdf.save('temp.pdf')
    pdf_buffer = open('temp.pdf', 'rb')
    
    return send_file(
        pdf_buffer,
        mimetype='application/pdf',
        as_attachment=True,
        download_name='converted.pdf'
    )

async def scrape_single_link(link,browserless_token,openAIKey):
    async with scraping_semaphore:
        conf = BrowserConfig(
    
            wss_url=f'wss://production-sfo.browserless.io/chrome/playwright?token={browserless_token}',
        )
        agent = Agent(
            
            browser=Browser(
                config=conf
            ),
            
            task=f"Go to {link} and find the name and price of the product as json object with the following keys: name, price. Only give the after tax price.",
            llm=ChatOpenAI(model="gpt-4o",api_key=openAIKey)
        )
        result = await agent.run()
        text = result.final_result()
        try:
            result = json.loads(text)
            return result
        except Exception as e:
            corrected_op = agent.llm.invoke("Make the json object valid and only respond with the object. no codeblocks, just the json object.: "+text).content
            try:
                corrected_op = json.loads(corrected_op)
                return corrected_op
            except Exception as e:
                return {}

async def scrape_links(task_id, links,openAIKey,browserless_token):
    try:
        # Create tasks for all links to be scraped in parallel
        tasks = [scrape_single_link(link,browserless_token=browserless_token,openAIKey=openAIKey) for link in links]
        # Wait for all scraping tasks to complete
        results = await asyncio.gather(*tasks)

        # Store final results
        scraping_results[task_id] = {
            'status': 'complete',
            'results': results
        }
        
    except Exception as e:
        scraping_results[task_id] = {
            'status': 'error',
            'error': str(e)
        }

    finally:
        if task_id in scraping_tasks:
            del scraping_tasks[task_id]

@app.route('/scrape_info', methods=['POST'])
def scrape_info():
    links = request.get_json()['links']
    openAIKey = request.get_json()['openAIKey']
    print(f"Received {len(links)} links to scrape")
    browserless_token = request.get_json()['browserless_token']
    task_id = str(uuid.uuid4())
    print(f"Starting scraping task with I45767D: {task_id}")
    # Start scraping in background
    loop = asyncio.new_event_loop()
    scraping_tasks[task_id] = Thread(target=lambda: loop.run_until_complete(scrape_links(task_id, links,openAIKey=openAIKey,browserless_token=browserless_token)))
    scraping_tasks[task_id].start()
    
    return jsonify({'task_id': task_id})

@app.route('/scrape_status/<task_id>', methods=['GET'])
def get_scrape_status(task_id):
    print(f"Checking status of task with ID: {task_id}")
    if task_id in scraping_tasks:
        return jsonify({'status': 'in_progress'})
    elif task_id in scraping_results:
        result = scraping_results[task_id]
        # Clean up results after sending
        del scraping_results[task_id]
        return jsonify(result)
    else:
        return jsonify({'status': 'not_found'}), 404

if __name__ == '__main__':
    app.run(port=45767, host="0.0.0.0") # os.environ.get('PORT',)
