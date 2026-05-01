import os, asyncio, discord
from dotenv import load_dotenv; load_dotenv()

BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
FORUM_CHANNEL_ID = int(os.getenv("DISCORD_FORUM_CHANNEL_ID"))
intents = discord.Intents.default()
bot = discord.Bot(intents=intents)  # or commands.Bot

@bot.event
async def on_ready():
    print("Bot ready:", bot.user)

async def create_forum(title, content):
    forum = bot.get_channel(FORUM_CHANNEL_ID)  # discord.ForumChannel
    thread = await forum.create_thread(name=title, content=content, auto_archive_duration=4320)
    return f"https://discord.com/channels/{thread.guild.id}/{thread.id}"

bot.run(BOT_TOKEN)