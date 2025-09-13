let isWorking = false;
let currentEarnings = 0;
let totalTrips = 0;

window.addEventListener('message', function(event) {
    const data = event.data;

    switch(data.action) {
        case 'showTaxiInfo':
            showTaxiInfo(data.show);
            break;

        case 'updateStatus':
            updateWorkingStatus(data.working);
            break;

        case 'showPassenger':
            showPassengerInfo(data.show, data.passenger);
            break;

        case 'updateTrip':
            updateTripProgress(data.progress, data.distance, data.fare);
            break;

        case 'updateStats':
            updateStats(data.earnings, data.trips);
            break;
    }
});

function showTaxiInfo(show) {
    const container = document.getElementById('taxi-info');

    if (show) {
        container.classList.remove('hidden');
    } else {
        container.classList.add('hidden');
    }
}

function updateWorkingStatus(working) {
    const container = document.getElementById('taxi-info');
    const statusText = container.querySelector('.status-text');
    const instructionText = container.querySelector('.instruction span');

    isWorking = working;

    if (working) {
        container.classList.add('working');
        statusText.textContent = 'Looking for passengers';
        instructionText.textContent = 'Stop working';
    } else {
        container.classList.remove('working');
        statusText.textContent = 'Ready for passengers';
        instructionText.textContent = 'Start accepting passengers';
    }
}

function showPassengerInfo(show, passengerData) {
    const container = document.getElementById('passenger-info');

    if (show && passengerData) {
        document.getElementById('passenger-name').textContent = passengerData.name;
        document.getElementById('destination').textContent = passengerData.destination;
        document.getElementById('distance').textContent = passengerData.distance + 'km';
        document.getElementById('fare').textContent = '$' + passengerData.fare;
        document.getElementById('progress').style.width = '0%';

        container.classList.remove('hidden');
    } else {
        container.classList.add('hidden');
    }
}

function updateTripProgress(progress, distance, fare) {
    const progressBar = document.getElementById('progress');
    const progressPercent = document.getElementById('progress-percent');
    const distanceElement = document.getElementById('distance');
    const fareElement = document.getElementById('fare');

    const progressPercentage = Math.round(progress * 100);
    progressBar.style.width = progressPercentage + '%';
    if (progressPercent) {
        progressPercent.textContent = progressPercentage + '%';
    }
    distanceElement.textContent = distance + 'km';
    fareElement.textContent = '$' + fare;
}

function updateStats(earnings, trips) {
    currentEarnings = earnings;
    totalTrips = trips;

    document.getElementById('earnings').textContent = '$' + earnings;
    document.getElementById('trips').textContent = trips;
}