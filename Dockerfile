FROM ruby:2.7.0-slim-buster

RUN apt-get update && apt-get install -y \
        poppler-utils \
        ocrmypdf \
        tesseract-ocr-deu \
        exiftool \
        make \
        git

RUN git config --global user.email "tech@200ok.ch" && \
        git config --global user.name "200ok Bot"

RUN mkdir /app
WORKDIR /app

ENV LANG C.UTF-8
