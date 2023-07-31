// Imports the Google Cloud client library
const { SpeechClient } = require('@google-cloud/speech');
const { createReadStream } = require('fs');
const path = require('path');
let transcription = "";

// get file name from command line
const fileName = process.argv[2];

// Creates a client
const client = new SpeechClient({
    // get auth key json file from  current directory
    keyFilename: path.join(__dirname, 'auth-key.json'),

});

const config = {
    encoding: 'LINEAR16',
    sampleRateHertz: "44100",
    languageCode: 'en-US',
    audioChannelCount: 2,
    enableAutomaticPunctuation: true,
};

const audioFilePath = fileName

const request = {
    config: config,
};


const recognizeStream = client
    .streamingRecognize(request)
    .on('error', error => {
        process.stdout.write(JSON.stringify({
            status: "error",
            error: error.message
        }));
    })
    .on('data', data => {
        const result = data.results[0].alternatives[0].transcript
        transcription += result;
    })
    .on('end', () => {
        process.stdout.write(JSON.stringify({
            status: "completed",
            text: transcription
        }));
    });

createReadStream(audioFilePath).pipe(recognizeStream);
