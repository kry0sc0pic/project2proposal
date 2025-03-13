import modal
from modal import image, App
from fastapi.requests import Request
from fastapi.responses import StreamingResponse

md_image = (image.Image.from_registry('python:3.11').pip_install('markdown_pdf'))
scrape_image = (image.Image.from_registry('python:3.11').pip_install('browser_use'))

app = App('Project2Proposal')

@app.function(image=md_image)
@modal.fastapi_endpoint(method="POST")
async def convert_md_to_pdf(request: Request):
    from markdown_pdf import MarkdownPdf, Section
    markdown_content = (await request.json())['markdown']
    pdf = MarkdownPdf()
    pdf.add_section(section=Section(markdown_content,toc=False))
    pdf.meta["title"] = "Proposal"
    pdf.meta["author"] = "Project2Proposal"
    pdf.save('temp.pdf')
    def iter_file():
        with open('temp.pdf', 'rb') as f:
            yield from f

    return StreamingResponse(iter_file(), media_type='application/pdf', headers={"Content-Disposition": "attachment; filename=converted.pdf"})


