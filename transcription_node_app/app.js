// Imports the Google Cloud client library
const { SpeechClient } = require('@google-cloud/speech');
const { Storage } = require('@google-cloud/storage')
const path = require('path')


const bucketName = 'bbb-transcription';
const serviceKey = path.join(__dirname, './auth-key.json')

let transcription = "";

// get file name from command line
const fileName = process.argv[2];
const meetingId = process.argv[3];

// Creates a client
const speechClient = new SpeechClient({
    // get auth key json file from  current directory
    keyFilename: serviceKey
});

// Create a storage client
const storage = new Storage({
    keyFilename: serviceKey
})

const bucket = storage.bucket(bucketName);


const config = {
    encoding: 'LINEAR16',
    sampleRateHertz: "44100",
    languageCode: 'en-US',
    audioChannelCount: 2,
    enableAutomaticPunctuation: true,
};

async function main() {
    try {
        const resp = await bucket.upload(fileName, {
            destination: `audios/${meetingId}.wav`,
        })

        console.log(resp)

        const request = {
            config: config,
            audio: {
                uri: `gs://${bucketName}/audios/${meetingId}.wav`,
            },

            outputConfig: {
                gcsUri: `gs://${bucketName}/transcriptions/${meetingId}.json`,
            },

            model: "default",
            processingStrategy: "DYNAMIC_BATCH"
        };

        const [operation] = speechClient.longRunningRecognize(request)
        await operation.promise()

        console.log("Transcription complete")
        // gcs public uri for transcription file
        console.log(`gs://${bucketName}/transcriptions/${meetingId}.json`)

    } catch (error) {
        console.log(error)
    }
}

main().catch(console.error);



