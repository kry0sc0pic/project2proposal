from markdown_pdf import MarkdownPdf, Section
import os
from flask import Flask, send_file, request
import io

app = Flask(__name__)

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

if __name__ == '__main__':
    app.run(port=os.environ.get('PORT',45767),)
