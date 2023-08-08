(function() {
    // Open a generic prompt to let the user choose either "whip" or "bard"
    let promptResult = prompt('Choose a character', 'whip');
    promptResult = promptResult.toLowerCase();
    promptResultTitle = promptResult.charAt(0).toUpperCase() + promptResult.slice(1);

    //  If previous loaded, remove it
    const idsToRemove = ['roe-send-button', 'roe-label'];
    idsToRemove.forEach(id => {
        if (document.getElementById(id)) {
            document.getElementById(id).remove();
        }
    });

    // Add watermark to the page
    // Create a new label element
    const label = document.createElement('div');
    label.id = 'roe-label';
    label.innerText = promptResultTitle;
    label.style.position = 'fixed';
    label.style.right = '10px';
    label.style.top = '50%';
    label.style.transform = 'translateY(-50%) rotate(-90deg)';
    label.style.fontFamily = 'Trebuchet MS, sans-serif';
    label.style.fontStyle = 'italic';
    label.style.fontSize = '24pt';
    label.style.color = 'rgba(0, 0, 0, 0.5)';
    label.style.pointerEvents = 'none';  // This makes the element non-blocking for clicks

    // Append the label to the body
    document.body.appendChild(label);

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

            // Send a change event to the textarea
            let event = new Event('input', { 'bubbles': true, 'cancelable': true });
            textarea.dispatchEvent(event);

            // Delay a half second ...
            setTimeout(() => {
                // Get the parent of the textarea
                let parentElement = textarea.parentElement;

                // Find the button within the same parent element
                let submitButton = parentElement.querySelector('button');

                // Simulate a realistic click event on the button
                if (submitButton) {
                    submitButton.click();
                } else {
                    console.log("Button not found!");
                }
            }, 500)

            // Show a button at the bottom of the page, just below the textarea, labelled "Send Message and Continue"
            const sendButton = document.createElement('button');
            sendButton.id = 'roe-send-button';
            sendButton.innerText = 'Send Message and Continue';
            sendButton.style.position = 'fixed';
            sendButton.style.bottom = '10px';
            sendButton.style.left = '50%';
            sendButton.style.transform = 'translateX(-50%)';
            sendButton.style.fontFamily = 'Trebuchet MS, sans-serif';
            sendButton.style.backgroundColor = '#bbb';
            sendButton.style.padding = '5px 20px';
            sendButton.style.color = '#333';
    
            // On click, call the sendLastMessage function
            sendButton.addEventListener('click', sendLastMessage);

            // Append the button to the body
            document.body.appendChild(sendButton);            
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

    const getClipboardContent = async () => {
        try {
            const text = await navigator.clipboard.readText();
            console.log('Clipboard content:', text);
            return text;
        } catch (err) {
            console.error('Failed to read clipboard:', err);
            return null;
        }
    }

    // Trigger the "Copy Last Message" routine, and then send the payload back to the server
    const sendLastMessage = () => {
        document.getElementById('roe-send-button').remove();

        let event = new KeyboardEvent('keydown', {
            metaKey : true,
            shiftKey : true,
            bubbles : true,
            cancelable : true,
            currentTarget : document,
            key : "c",
        })
        document.dispatchEvent(event);

        setTimeout(() => {getClipboardContent().then(content => {
            if (content !== null) {
                console.log('Read from clipboard:', content);
            }
        }) }, 1000)
    }

    return connect_to_websocket();
})();