(function() {
    // Open a generic prompt to let the user choose either "whip" or "bard"
    let promptResult = prompt('Choose a character', 'whip');

    const channel = promptResult+":lobby";
    const url = 'wss://abandoned-scared-halibut.gigalixirapp.com/socket/websocket';

    // Declare a global variable to hold the WebSocket connection
    window.roeSocket = window.roeSocket || null;

    // Check if a connection already exists and close it
    if (window.roeSocket !== null) {
        console.log('Closing existing connection');
        window.roeSocket.close(3001, 'Switching to new connection');
        window.roeSocket = null;
    }

    const onOpen = function (event) {
        console.log('Connection opened');

        // Send the join message payload as soon as the connection is opened
        const uniqueRef = Math.floor(Math.random() * 1000000000);
        let joinMessage = {
            topic: channel,
            event: 'phx_join',
            payload: {},
            ref: uniqueRef // This can be a unique reference value for each message
        };
        console.log('Sending join message', joinMessage);
        window.roeSocket.send(JSON.stringify(joinMessage));
    };

    const onmessage = function (event) {
        // console.log('Received data', event.data);

        // Now you can handle incoming messages
        let incomingMessage = JSON.parse(event.data);
        if (incomingMessage.event === 'phx_reply' && incomingMessage.payload.status === 'ok') {
            console.log('Joined successfully to the channel');
        } else if (incomingMessage.event === 'message:new') {
            console.log('New Message: ' + incomingMessage.payload.body);

            // Find the textarea by its ID
            let textarea = document.getElementById('prompt-textarea');

            // Set the textarea value
            textarea.value = incomingMessage.payload.body;
        }
    };

    const onerror = function (error) {
        console.log('WebSocket error: ', error);
    };

    const onclose = function(event) {
        console.log('WebSocket connection closed: ', event);

        // If the socket was closed for a reason other than the client closing it, try to reconnect
        if (event.code === 1006 ) {
            // Wait 3 seconds before trying to reconnect
            setTimeout(function() {
                console.log('Trying to reconnect...');
                connect_to_websocket();
            }, 3000);
        } else if (event.code !== 3001 && event.code !== 1006) {
            console.log('Trying to reconnect...');
            connect_to_websocket();
        }
    };

    // Create a new WebSocket connection
    const connect_to_websocket = function() {
        window.roeSocket = new WebSocket(url);
        window.roeSocket.onopen = onOpen;
        window.roeSocket.onmessage = onmessage;
        window.roeSocket.onerror = onerror;
        window.roeSocket.onclose = onclose;

        return window.roeSocket;
    }

    return connect_to_websocket();
})();