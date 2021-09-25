from src import app
from flask import Flask, jsonify


@app.route('/')
def index():
    return jsonify(message="hello, world!")
