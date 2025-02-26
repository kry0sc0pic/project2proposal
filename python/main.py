from langchain_openai import ChatOpenAI
from browser_use import Agent
import asyncio
from dotenv import load_dotenv
import json
load_dotenv()

async def main():
    agent = Agent(
        task="Go to https://evelta.com/2805-140kv-gimbal-brushless-motor-for-3-axis-camera-gimbal/ and find the name and price of the product as json object. only give the after tax price.",
        llm=ChatOpenAI(model="gpt-4o",api_key="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"),
        generate_gif=False,

    )
    result = await agent.run()
    try:
        result = json.loads(result)
        print(result)
    except Exception as e:
        print(result)
        corrected_op = agent.llm.invoke("Make the json object valid: "+result).content
        print(corrected_op)
        try:
            corrected_op = json.loads(corrected_op)
            print(corrected_op)
        except Exception as e:
            print(corrected_op)
            print("Could not convert to json object")
            print("Error:",e)
            print("Please try again")
            return


asyncio.run(main())